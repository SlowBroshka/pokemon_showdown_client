import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/decisions/battle_decision_controller.dart';
import 'package:pokemon_showdown_client/core/protocol/client_commands.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../../transport/support/fake_socket_channel.dart';

Future<void> drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  final cases =
      (jsonDecode(File('test/fixtures/battle/requests.json').readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List;
  String request(String id) {
    final fixture = cases.cast<Map<String, dynamic>>().firstWhere(
      (c) => c['id'] == id,
    );
    return '|request|${fixture.containsKey('rawPayload') ? fixture['rawPayload'] : jsonEncode(fixture['payload'])}';
  }

  late FakeSocketChannel socket;
  late ShowdownSession session;
  late BattleDecisionController controller;

  setUp(() async {
    socket = FakeSocketChannel();
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    final connecting = session.connect(Uri.parse('wss://example.test'));
    socket.handshake.complete();
    await connecting;
    await drain();
    controller = BattleDecisionController(
      session: session,
      roomId: 'battle-contract-1',
    );
    socket.incoming.add(
      '>battle-contract-1\n|init|battle\n|gen|9\n|gametype|singles\n|start\n|turn|1\n${request('move')}',
    );
    await drain();
  });
  tearDown(() async {
    await controller.dispose();
    await session.dispose();
    await socket.incoming.close();
  });
  Future<void> receive(
    String lines, {
    String room = 'battle-contract-1',
  }) async {
    socket.incoming.add('>$room\n$lines');
    await drain();
  }

  bool choose([BattleChoice choice = const BattleChoice.move(1)]) {
    final captured = controller.capture(choice);
    return captured != null && controller.submit(captured);
  }

  test('serializes typed choices and rejects invalid wire fields', () {
    expect(
      ChooseCommand(
        roomId: 'battle-a',
        choice: const BattleChoice.move(1),
        rqid: 7,
      ).serialize(),
      'battle-a|/choose move 1|7',
    );
    expect(
      ChooseCommand(
        roomId: 'battle-a',
        choice: const BattleChoice.move(2, terastallize: true),
      ).serialize(),
      'battle-a|/choose move 2 terastallize',
    );
    expect(
      ChooseCommand(
        roomId: 'battle-a',
        choice: const BattleChoice.switchTo(6),
        rqid: 0,
      ).serialize(),
      'battle-a|/choose switch 6|0',
    );
    for (final room in ['a|b', 'a\nb', '', ' a']) {
      expect(
        () => ChooseCommand(roomId: room, choice: const BattleChoice.move(1)),
        throwsArgumentError,
      );
    }
    for (final choice in [
      const BattleChoice.move(0),
      const BattleChoice.move(5),
      const BattleChoice.switchTo(7),
    ]) {
      expect(
        () => ChooseCommand(roomId: 'battle-a', choice: choice),
        throwsArgumentError,
      );
    }
    expect(
      () => ChooseCommand(
        roomId: 'battle-a',
        choice: const BattleChoice.move(1),
        rqid: -1,
      ),
      throwsArgumentError,
    );
  });

  test('sends once, without interpreting socket write as acceptance', () {
    expect(controller.canChoose, isTrue);
    final captured = controller.capture(const BattleChoice.move(1))!;
    expect(controller.submit(captured), isTrue);
    expect(controller.submit(captured), isFalse);
    expect(controller.phase, BattleDecisionPhase.submitted);
    expect(socket.sink.sent, ['battle-contract-1|/choose move 1|7']);
  });
  test('validates availability and tera against latest request', () async {
    expect(choose(const BattleChoice.move(4)), isFalse);
    expect(choose(const BattleChoice.move(1, terastallize: true)), isFalse);
    expect(choose(const BattleChoice.switchTo(1)), isFalse);
    await receive(request('tera'));
    expect(choose(const BattleChoice.move(1, terastallize: true)), isTrue);
    expect(socket.sink.sent.single, contains('move 1 terastallize|'));
  });
  test('voluntary and forced switches use team positions', () async {
    expect(choose(const BattleChoice.switchTo(2)), isTrue);
    await receive(request('force-switch'));
    expect(choose(), isFalse);
    expect(choose(const BattleChoice.switchTo(2)), isTrue);
  });
  test('trapped request disallows voluntary switch', () async {
    await receive(request('trapped'));
    expect(choose(const BattleChoice.switchTo(2)), isFalse);
    expect(choose(), isTrue);
  });
  test('same rqid still invalidates captured revision', () async {
    final old = controller.capture(const BattleChoice.move(1))!;
    await receive(request('same-rqid-changed'));
    expect(controller.submit(old), isFalse);
    expect(socket.sink.sent, isEmpty);
  });
  test('missing rqid omits suffix', () async {
    await receive(request('no-rqid'));
    expect(choose(), isTrue);
    expect(socket.sink.sent.single, 'battle-contract-1|/choose move 1');
  });
  for (final id in [
    'wait',
    'clear',
    'broken-json',
    'team-preview',
    'doubles',
  ]) {
    test('$id replaces and blocks a previous valid choice', () async {
      final old = controller.capture(const BattleChoice.move(1))!;
      await receive(request(id));
      expect(controller.submit(old), isFalse);
      expect(controller.canChoose, isFalse);
    });
  }
  test('current invalid choice allows correction, unavailable waits', () async {
    expect(choose(), isTrue);
    await receive('|error|[Invalid choice] Synthetic refusal');
    expect(controller.canChoose, isTrue);
    expect(choose(const BattleChoice.switchTo(2)), isTrue);
    await receive('|error|[Unavailable choice] Synthetic refusal');
    expect(controller.phase, BattleDecisionPhase.awaitingRequest);
    expect(choose(), isFalse);
    await receive(request('move'));
    expect(choose(), isTrue);
  });
  test('late errors never reopen a superseded choice', () async {
    expect(choose(), isTrue);
    await receive(request('move'));
    await receive('|error|[Invalid choice] Old refusal');
    expect(controller.canChoose, isTrue);
    expect(choose(), isTrue);
    await receive('|error|[Invalid choice] Ambiguous refusal');
    expect(controller.phase, BattleDecisionPhase.awaitingRequest);
    expect(choose(), isFalse);
  });
  test(
    'unrelated rooms and generic errors do not release pending send',
    () async {
      expect(choose(), isTrue);
      await receive('|error|[Invalid choice] Wrong room', room: 'battle-other');
      await receive('|error|Some other error\n|message|A message');
      expect(controller.phase, BattleDecisionPhase.submitted);
      expect(choose(), isFalse);
    },
  );
  test('never sends between records of a single source frame', () async {
    final attempts = <bool>[];
    final subscription = session.updates.listen((update) {
      if (update.event is BattleRequestEvent) attempts.add(choose());
    });
    await receive('${request('move')}\n${request('wait')}');
    expect(attempts, [false, false]);
    expect(socket.sink.sent, isEmpty);
    expect(controller.canChoose, isFalse);
    await subscription.cancel();
  });
  test('source receipt blocks choice before controller delivery', () async {
    final old = controller.capture(const BattleChoice.move(1))!;
    // Transport publishes first; the controller has not consumed its routed
    // notification when this source listener runs.
    bool? attempted;
    final sub = session.roomChanges.listen((_) {
      attempted = controller.submit(old);
    });
    await receive('|title|Changed\n${request('wait')}');
    expect(attempted, isFalse);
    expect(socket.sink.sent, isEmpty);
    await sub.cancel();
  });
  for (final end in [
    '|win|ExamplePlayer',
    '|tie|',
    '|deinit|',
    '|gametype|doubles',
  ]) {
    test('$end blocks further choices', () async {
      await receive(end);
      expect(choose(), isFalse);
    });
  }
  test('disconnect invalidates captured choice and never resends', () async {
    final old = controller.capture(const BattleChoice.move(1))!;
    await session.disconnect();
    expect(controller.submit(old), isFalse);
    await drain();
    expect(controller.state.stale, isTrue);
    expect(controller.phase, BattleDecisionPhase.inactive);
    expect(socket.sink.sent, isEmpty);
  });
  test('send failure is uncertain and is never retried', () {
    socket.sink.failSend = true;
    expect(choose(), isFalse);
    expect(controller.phase, BattleDecisionPhase.uncertain);
    socket.sink.failSend = false;
    expect(choose(), isFalse);
    expect(socket.sink.sent, isEmpty);
  });
  test('timeout marks uncertain; new request is required', () async {
    await controller.dispose();
    controller = BattleDecisionController(
      session: session,
      roomId: 'battle-contract-1',
      responseTimeout: const Duration(milliseconds: 10),
    );
    await receive(
      '|init|battle\n|gen|9\n|gametype|singles\n|start\n${request('move')}',
    );
    expect(choose(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.phase, BattleDecisionPhase.uncertain);
    expect(choose(), isFalse);
    await receive(request('move'));
    expect(controller.canChoose, isTrue);
    expect(socket.sink.sent, hasLength(1));
  });
  test(
    'empty frames advance source progress without blocking the next choice',
    () async {
      for (final frame in ['', '\n\n', '>battle-contract-1']) {
        socket.incoming.add(frame);
        await drain();
        expect(controller.canChoose, isTrue);
      }
      expect(choose(), isTrue);
    },
  );
  test('context from another room or epoch cannot be submitted', () {
    final valid = controller.capture(const BattleChoice.move(1))!;
    for (final wrong in [
      CapturedBattleChoice(
        roomId: 'battle-other',
        connectionEpoch: valid.connectionEpoch,
        requestRevision: valid.requestRevision,
        rqid: valid.rqid,
        choice: valid.choice,
      ),
      CapturedBattleChoice(
        roomId: valid.roomId,
        connectionEpoch: valid.connectionEpoch + 1,
        requestRevision: valid.requestRevision,
        rqid: valid.rqid,
        choice: valid.choice,
      ),
      CapturedBattleChoice(
        roomId: valid.roomId,
        connectionEpoch: valid.connectionEpoch,
        requestRevision: valid.requestRevision,
        rqid: 999,
        choice: valid.choice,
      ),
    ]) {
      expect(controller.submit(wrong), isFalse);
    }
    expect(socket.sink.sent, isEmpty);
  });
  test(
    'reconnection never revives the old controller or resends a choice',
    () async {
      expect(choose(), isTrue);
      await session.disconnect();
      await drain();
      final first = socket;
      socket = FakeSocketChannel();
      final connecting = session.connect(Uri.parse('wss://example.test'));
      socket.handshake.complete();
      await connecting;
      await receive(
        '|init|battle\n|gen|9\n|gametype|singles\n|start\n${request('move')}',
      );
      expect(controller.canChoose, isFalse);
      expect(controller.state.stale, isTrue);
      expect(first.sink.sent, hasLength(1));
      expect(socket.sink.sent, isEmpty);
      await first.incoming.close();
    },
  );
  test('disposing session disables choices synchronously', () async {
    final pending = session.dispose();
    expect(controller.canChoose, isFalse);
    await pending;
    await drain();
    expect(controller.phase, BattleDecisionPhase.inactive);
  });
  test('dispose leaves shared session connected and disables writes', () async {
    final old = controller.capture(const BattleChoice.move(1))!;
    await controller.dispose();
    expect(controller.submit(old), isFalse);
    expect(session.status, TransportStatus.connected);
  });
}
