import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/decisions/battle_decision_controller.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_phase.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';

import '../../core/transport/support/fake_socket_channel.dart';

Future<void> drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  final fixtures = jsonDecode(
    File('test/fixtures/battle/requests.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final move = (fixtures['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((c) => c['id'] == 'move')['payload'];
  final request = '|request|${jsonEncode(move)}';
  final initial =
      '|init|battle\n|title|Prepared battle\n|gen|9\n|gametype|singles\n|start\n|turn|1\n$request';
  late FakeSocketChannel socket;
  late ShowdownSession session;
  late ConnectionController owner;

  Future<void> connect() async {
    final pending = owner.connect('wss://example.test');
    socket.handshake.complete();
    await pending;
    await drain();
  }

  Future<void> receive(String lines, {String room = 'battle-test'}) async {
    socket.incoming.add('>$room\n$lines');
    await drain();
  }

  Future<BattleDecisionController> joinBattle() async {
    owner.join('battle-test');
    await receive(initial);
    return owner.battle!;
  }

  setUp(() async {
    socket = FakeSocketChannel();
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    owner = ConnectionController(session: session);
    await connect();
  });
  tearDown(() async {
    owner.dispose();
    await owner.closed;
    await session.dispose();
    await socket.incoming.close();
  });

  test(
    'explicit join consumes first frame and chooses on the shared socket',
    () async {
      owner.join('battle-test');
      expect(owner.battle, isNull);
      expect(owner.joiningId, 'battle-test');
      await receive(initial);
      final battle = owner.battle!;
      expect(owner.room!.type, 'battle');
      expect(owner.room!.title, 'Prepared battle');
      expect(battle.state.phase, BattlePhase.started);
      expect(battle.state.requestRevision, 1);
      expect(battle.canChoose, isTrue);
      expect(
        battle.submit(battle.capture(const BattleChoice.move(1))!),
        isTrue,
      );
      expect(socket.sink.sent, [
        '|/join battle-test',
        'battle-test|/choose move 1|7',
      ]);
    },
  );
  test('room ID does not determine room type', () async {
    owner.join('custom');
    await receive(initial, room: 'custom');
    expect(owner.battle!.state.roomId, 'custom');
    expect(owner.battle!.canChoose, isTrue);
  });
  test('chat joins retain existing behavior and expose no battle', () async {
    owner.join('lobby');
    await receive('|init|chat\n|title|Lobby', room: 'lobby');
    expect(owner.battle, isNull);
    expect(owner.room!.type, 'chat');
    owner.leave();
    await receive('|deinit', room: 'lobby');
    expect(owner.canJoin, isTrue);
    expect(socket.sink.sent, ['|/join lobby', 'lobby|/leave']);
  });
  test('unsolicited battle cannot replace pending or selected room', () async {
    owner.join('battle-test');
    await receive(initial, room: 'battle-other');
    expect(owner.battle, isNull);
    expect(owner.joiningId, 'battle-test');
    await receive(initial);
    final selected = owner.battle;
    await receive(initial, room: 'battle-third');
    expect(owner.battle, same(selected));
    expect(owner.room!.id, 'battle-test');
    expect(socket.sink.sent, [
      '|/join battle-test',
      'battle-other|/leave',
      'battle-third|/leave',
    ]);
    expect(selected!.canChoose, isTrue);
  });
  test('duplicate init keeps context and request revision', () async {
    final battle = await joinBattle();
    final captured = battle.capture(const BattleChoice.move(1))!;
    await receive('|init|battle');
    expect(owner.battle, same(battle));
    expect(battle.state.requestRevision, 1);
    expect(battle.submit(captured), isTrue);
  });
  test(
    'leave revokes captured choices synchronously and waits for deinit',
    () async {
      final battle = await joinBattle();
      final captured = battle.capture(const BattleChoice.move(1))!;
      owner.leave();
      expect(battle.submit(captured), isFalse);
      expect(battle.canChoose, isFalse);
      expect(owner.canJoin, isFalse);
      await receive('|init|battle\n$request');
      expect(owner.leaving, isTrue);
      expect(battle.canChoose, isFalse);
      owner.leave();
      expect(socket.sink.sent, ['|/join battle-test', 'battle-test|/leave']);
      await receive('|deinit');
      expect(owner.room, isNull);
      expect(owner.battle, same(battle));
      expect(battle.state.phase, BattlePhase.closed);
      expect(owner.canJoin, isTrue);
    },
  );
  test(
    'win then deinit preserves the final result without creating a loss',
    () async {
      final battle = await joinBattle();
      await receive('|win|ExamplePlayer\n|deinit');
      expect(owner.battle, same(battle));
      expect(battle.state.result!.winner, 'ExamplePlayer');
      expect(battle.state.phase, BattlePhase.closed);
      expect(battle.canChoose, isFalse);
    },
  );
  test('deinit without a result is not a defeat', () async {
    final battle = await joinBattle();
    await receive('|deinit');
    expect(battle.state.result, isNull);
    expect(battle.state.phase, BattlePhase.closed);
    expect(owner.canJoin, isTrue);
  });
  test(
    'same-room rejoin rejects previous visit choices with identical rqid',
    () async {
      final previous = await joinBattle();
      final old = previous.capture(const BattleChoice.move(1))!;
      owner.leave();
      await receive('|deinit');
      final current = await joinBattle();
      expect(current, isNot(same(previous)));
      expect(current.state.connectionEpoch, previous.state.connectionEpoch);
      expect(current.state.requestRevision, old.requestRevision);
      expect(current.state.request!.rqid, old.rqid);
      expect(current.submit(old), isFalse);
      expect(previous.submit(old), isFalse);
      expect(
        current.submit(current.capture(const BattleChoice.move(1))!),
        isTrue,
      );
    },
  );
  test(
    'disconnect preserves stale snapshot and reconnect does not autojoin',
    () async {
      final previous = await joinBattle();
      final captured = previous.capture(const BattleChoice.move(1))!;
      final disconnecting = owner.disconnect();
      expect(previous.submit(captured), isFalse);
      await disconnecting;
      await drain();
      expect(owner.battle, same(previous));
      expect(previous.state.stale, isTrue);
      expect(previous.state.request, isNull);
      final oldSocket = socket;
      socket = FakeSocketChannel();
      await connect();
      expect(owner.battle, isNull);
      expect(owner.room, isNull);
      expect(socket.sink.sent, isEmpty);
      final current = await joinBattle();
      expect(current.submit(captured), isFalse);
      expect(current.canChoose, isTrue);
      await oldSocket.incoming.close();
    },
  );
  test(
    'server closes connection: snapshot remains but choices are disabled',
    () async {
      final battle = await joinBattle();
      socket.incoming.addError(StateError('private details'));
      await drain();
      expect(owner.room!.isStale, isTrue);
      expect(battle.state.stale, isTrue);
      expect(battle.canChoose, isFalse);
      expect(owner.notices.join(), isNot(contains('private details')));
    },
  );
  test(
    'battle changes notify owner even without room metadata changes',
    () async {
      final battle = await joinBattle();
      var changed = 0;
      owner.addListener(() => changed++);
      await receive('|turn|2\n$request');
      expect(changed, greaterThan(0));
      expect(battle.state.turn, 2);
      changed = 0;
      battle.submit(battle.capture(const BattleChoice.move(1))!);
      await drain();
      expect(changed, greaterThan(0));
    },
  );
  test('type-changing duplicate init fails closed', () async {
    final battle = await joinBattle();
    await receive('|init|chat');
    expect(owner.status, TransportStatus.disconnected);
    expect(battle.canChoose, isFalse);
    expect(owner.room!.type, 'battle');
  });
  test('failed join frees pending context without exposing a battle', () async {
    owner.join('battle-test');
    await receive('|noinit|joinfailed|Synthetic failure');
    expect(owner.status, TransportStatus.disconnected);
    expect(owner.battle, isNull);
    expect(owner.joiningId, isNull);
  });
  test(
    'disposing shared session immediately disables join and leave',
    () async {
      final pending = session.dispose();
      expect(owner.canJoin, isFalse);
      expect(() => owner.join('battle-test'), returnsNormally);
      await pending;
      expect(owner.battle, isNull);
      expect(socket.sink.sent, isEmpty);
    },
  );
  test(
    'late init after join timeout cannot revive the pending battle',
    () async {
      owner.dispose();
      await owner.closed;
      owner = ConnectionController(
        session: session,
        roomTimeout: const Duration(milliseconds: 10),
      );
      owner.join('battle-test');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await receive(initial);
      expect(owner.status, TransportStatus.disconnected);
      expect(owner.battle, isNull);
      expect(owner.room, isNull);
      expect(socket.sink.sent, ['|/join battle-test']);
    },
  );
  test(
    'foreign requests and deinit do not close or change selected battle',
    () async {
      final battle = await joinBattle();
      await receive('|request|null\n|deinit', room: 'battle-other');
      expect(owner.battle, same(battle));
      expect(owner.room!.id, 'battle-test');
      expect(battle.state.requestRevision, 1);
      expect(battle.canChoose, isTrue);
    },
  );
  test('leave failure disconnects without permitting another choice', () async {
    final battle = await joinBattle();
    final captured = battle.capture(const BattleChoice.move(1))!;
    socket.sink.failSend = true;
    owner.leave();
    expect(battle.submit(captured), isFalse);
    await drain();
    expect(owner.status, TransportStatus.disconnected);
    expect(battle.canChoose, isFalse);
  });
  test(
    'owner disposal revokes battle but leaves shared session open',
    () async {
      final battle = await joinBattle();
      final captured = battle.capture(const BattleChoice.move(1))!;
      owner.dispose();
      expect(battle.submit(captured), isFalse);
      await owner.closed;
      expect(session.status, TransportStatus.connected);
      await receive('$request\n|turn|2');
      expect(battle.state.turn, 1);
    },
  );
}
