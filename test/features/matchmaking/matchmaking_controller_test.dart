import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pokemon_showdown_client/core/auth/auth_api_client.dart';
import 'package:pokemon_showdown_client/core/auth/auth_controller.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_controller.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';
import 'package:pokemon_showdown_client/features/rooms/room_handoff_phase.dart';
import 'package:pokemon_showdown_client/features/rooms/room_owner.dart';

import '../../core/auth/support/fake_auth_http_client.dart';
import '../../core/transport/support/fake_socket_channel.dart';

const baseline = '|updatesearch|{"searching":[],"games":null}';
const queued = '|updatesearch|{"searching":["gen9randombattle"],"games":null}';
const formats = '|formats|,1|Singles|[Gen 9] Random Battle,4f';
const identity = '|updateuser| ExamplePlayer|1|1|{}';
const room = 'battle-gen9randombattle-contract1';
const found = '|updatesearch|{"searching":[],"games":{"$room":"Match"}}';
const initial =
    '>$room\n|init|battle\n|player|p1|ExamplePlayer\n|player|p2|Other\n|gen|9\n|gametype|singles\n|start';
const startCommands = ['|/utm null', '|/search gen9randombattle'];
const cancelCommand = '|/cancelsearch gen9randombattle';

Future<void> drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeSocketChannel socket;
  late List<FakeSocketChannel> sockets;
  late ShowdownSession session;
  late AuthController auth;
  late FormatCatalogController catalog;
  late RoomOwner rooms;
  late MatchmakingController controller;

  Future<void> receive(String value) async {
    socket.incoming.add(value);
    await drain();
  }

  Future<void> connect({bool login = true}) async {
    final future = session.connect(
      Uri.parse('wss://sim3.psim.us/showdown/websocket'),
    );
    socket.handshake.complete();
    await future;
    await receive('|challstr|0|synthetic-challenge');
    if (login) {
      final pending = auth.login(
        username: 'ExamplePlayer',
        password: 'synthetic',
      );
      await drain();
      await receive(identity);
      await pending;
    }
    await receive('$formats\n$baseline');
    socket.sink.sent.clear();
  }

  setUp(() async {
    socket = FakeSocketChannel();
    sockets = [socket];
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    auth = AuthController(
      session: session,
      api: AuthApiClient(
        clientFactory: () => FakeAuthHttpClient(
          (_) => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                ']${jsonEncode({
                  'curuser': {'loggedin': true, 'username': 'ExamplePlayer'},
                  'assertion': 'synthetic,exampleplayer,2,0,example.invalid;not-a-signature',
                })}',
              ),
            ),
            200,
          ),
        ),
      ),
    );
    catalog = FormatCatalogController(session: session);
    rooms = RoomOwner(
      session,
      handoffTimeout: const Duration(milliseconds: 80),
    );
    controller = MatchmakingController(
      session: session,
      auth: auth,
      catalog: catalog,
      rooms: rooms,
      experimentalEnabled: true,
      responseTimeout: const Duration(milliseconds: 80),
    );
    await connect();
  });

  tearDown(() async {
    await controller.dispose();
    rooms.dispose();
    await rooms.closed;
    await catalog.dispose();
    await auth.dispose();
    await session.dispose();
    for (final socket in sockets) {
      await socket.incoming.close();
    }
  });

  void start() {
    expect(controller.canStart, isTrue);
    expect(controller.start(controller.captureStart()!), isTrue);
  }

  test(
    'start reserves before sends and send success is not queue confirmation',
    () {
      socket.sink.onSend = (_) =>
          expect(rooms.handoffPhase, RoomHandoffPhase.reserved);
      final action = controller.captureStart()!;
      expect(controller.start(action), isTrue);
      expect(controller.state.phase, MatchmakingPhase.submitting);
      expect(controller.start(action), isFalse);
      rooms.join('lobby');
      expect(socket.sink.sent, startCommands);
    },
  );

  // Execute the original ordered corpus against production controllers. Only
  // supported step kinds are selected explicitly; no expectation is simulated.
  final corpus = jsonDecode(
    File('test/fixtures/matchmaking/scenarios.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final messages = jsonDecode(
    File('test/fixtures/matchmaking/messages.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final wires = {
    for (final entry in messages['cases'] as List)
      entry['id'] as String: entry['wire'] as String,
  };
  const executable = {
    'search-found',
    'immediate-match',
    'cancel-observed-not-ack',
    'cancel-loses-to-match',
    'early-cancel-late-queue',
    'early-cancel-no-reply',
    'cancel-missing-queue-no-reply',
    'double-start',
    'double-cancel',
    'popup-is-not-final-rejection',
    'error-is-not-correlated-ack',
    'malformed-does-not-cancel',
    'wrong-scope-ignored',
    'catalog-removed-during-search',
    'catalog-malformed-before-start',
    'external-queue-blocks',
    'existing-game-blocks',
    'multiple-games-conflict',
    'init-before-games',
    'duplicate-init',
    'spectator-not-owned',
    'candidate-timeout',
  };
  for (final scenario
      in (corpus['scenarios'] as List).cast<Map<String, dynamic>>().where(
        (s) => executable.contains(s['id']),
      )) {
    test('contract: ${scenario['id']}', () async {
      for (final step
          in (scenario['steps'] as List).cast<Map<String, dynamic>>()) {
        final before = socket.sink.sent.length;
        switch (step['action']) {
          case 'start':
            final action = controller.captureStart();
            if (action != null) controller.start(action);
          case 'cancel':
            final token = controller.state.attemptToken;
            if (token != null) controller.cancel(token);
          case 'timeout':
            await Future<void>.delayed(const Duration(milliseconds: 120));
          case null:
            await receive(
              step['receiveFixture'] != null
                  ? wires[step['receiveFixture']]!
                  : step['receive'] as String,
            );
          default:
            fail('Unimplemented action: ${step['action']}');
        }
        final expected = step['expect'] as Map<String, dynamic>;
        if (expected.containsKey('phase')) {
          expect(controller.state.phase.name, expected['phase']);
        }
        if (expected.containsKey('send')) {
          expect(socket.sink.sent.skip(before).toList(), expected['send']);
        }
        if (expected.containsKey('canStart')) {
          expect(controller.canStart, expected['canStart']);
        }
        if (expected.containsKey('selectedRoom')) {
          expect(rooms.room?.id, expected['selectedRoom']);
        }
        if (expected.containsKey('notice')) {
          expect(controller.state.notice?.name, expected['notice']);
        }
        if (expected['battleContexts'] == 1) expect(rooms.battle, isNotNull);
      }
    });
  }

  test('default experimental gate is closed', () async {
    await controller.dispose();
    controller = MatchmakingController(
      session: session,
      auth: auth,
      catalog: catalog,
      rooms: rooms,
    );
    await receive('$formats\n$baseline');
    expect(controller.captureStart(), isNull);
    expect(socket.sink.sent, isEmpty);
  });

  test('named user without authenticated account cannot start', () async {
    await session.disconnect();
    socket = FakeSocketChannel();
    sockets.add(socket);
    await connect(login: false);
    await receive(identity);
    expect(controller.canStart, isFalse);
    expect(socket.sink.sent, isEmpty);
  });

  test('manual join blocks start', () {
    rooms.join('battle-manual');
    expect(controller.captureStart(), isNull);
    expect(socket.sink.sent, ['|/join battle-manual']);
  });

  test('captured start invalidated by even an unrelated new frame', () async {
    final action = controller.captureStart()!;
    await receive('|message|source advanced');
    expect(controller.start(action), isFalse);
    expect(socket.sink.sent, isEmpty);
    expect(controller.canStart, isTrue);
  });

  test(
    'queued source progress blocks action before controller delivery',
    () async {
      final action = controller.captureStart()!;
      final checked = Completer<void>();
      final subscription = session.updates.listen((_) {
        expect(controller.start(action), isFalse);
        if (!checked.isCompleted) checked.complete();
      });
      socket.incoming.add('|formats|');
      await checked.future;
      await subscription.cancel();
      await drain();
      expect(socket.sink.sent, isEmpty);
    },
  );

  test(
    'catalog and gate removal do not prevent targeted cancel or own battle',
    () async {
      start();
      await receive(queued);
      controller.experimentalEnabled = false;
      await receive('|formats|bad');
      expect(controller.cancel(controller.state.attemptToken!), isTrue);
      await receive('$found\n$initial');
      expect(controller.state.phase, MatchmakingPhase.inBattle);
      expect(socket.sink.sent, [...startCommands, cancelCommand]);
    },
  );

  test('late queue plus game in same frame suppresses extra cancel', () async {
    start();
    controller.cancel(controller.state.attemptToken!);
    await receive('$queued\n$found\n$initial');
    expect(controller.state.phase, MatchmakingPhase.inBattle);
    expect(socket.sink.sent, [...startCommands, cancelCommand]);
  });

  test(
    'empty snapshots and duplicates cannot extend cancel deadline',
    () async {
      start();
      controller.cancel(controller.state.attemptToken!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await receive(baseline);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.state.phase, MatchmakingPhase.outcomeUnknown);
      expect(controller.canStart, isFalse);
      expect(rooms.canJoin, isFalse);
    },
  );

  test('late confirmed match after response timeout still wins', () async {
    start();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller.state.phase, MatchmakingPhase.outcomeUnknown);
    await receive('$found\n$initial');
    expect(controller.state.phase, MatchmakingPhase.inBattle);
    expect(socket.sink.sent, startCommands);
  });

  test('first request is delivered once through the existing owner', () async {
    final data = jsonDecode(
      File('test/fixtures/battle/requests.json').readAsStringSync(),
    );
    final request = (data['cases'] as List).firstWhere(
      (v) => v['id'] == 'move',
    )['payload'];
    start();
    await receive('$found\n$initial\n|request|${jsonEncode(request)}');
    expect(controller.state.phase, MatchmakingPhase.inBattle);
    expect(rooms.battle!.state.requestRevision, 1);
    expect(rooms.battle!.canChoose, isTrue);
  });

  for (final command in startCommands) {
    test(
      'failure of $command prevents subsequent commands and retry',
      () async {
        final action = controller.captureStart()!;
        socket.sink.onSend = (value) {
          if (value == command) throw StateError('private-error');
        };
        expect(controller.start(action), isFalse);
        await drain();
        expect(controller.state.phase, MatchmakingPhase.disconnected);
        expect(controller.state.notice, MatchmakingNotice.sendFailed);
        expect(controller.start(action), isFalse);
        expect(
          socket.sink.sent,
          command == startCommands.first ? [] : [startCommands.first],
        );
      },
    );
  }

  test('state change between preparation and search blocks search send', () {
    socket.sink.onSend = (value) {
      if (value == startCommands.first) controller.experimentalEnabled = false;
    };
    expect(controller.start(controller.captureStart()!), isFalse);
    expect(controller.state.phase, MatchmakingPhase.outcomeUnknown);
    expect(socket.sink.sent, [startCommands.first]);
    expect(rooms.canJoin, isFalse);
  });

  test('identity change forbids cancellation', () async {
    start();
    final token = controller.state.attemptToken!;
    await receive('|updateuser| Other|1|1|{}');
    expect(controller.cancel(token), isFalse);
    expect(socket.sink.sent, startCommands);
    expect(controller.canStart, isFalse);
  });

  test(
    'immediate reconnect drops old attempt and requires new account baseline',
    () async {
      final action = controller.captureStart()!;
      start();
      final token = controller.state.attemptToken!;
      await session.disconnect();
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect();
      expect(controller.state.phase, MatchmakingPhase.idle);
      expect(controller.start(action), isFalse);
      start();
      expect(controller.cancel(token), isFalse);
      expect(socket.sink.sent, startCommands);
    },
  );

  test(
    'dispose cancels timers and subscriptions but preserves shared owners',
    () async {
      start();
      await controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(session.status, TransportStatus.connected);
      expect(rooms.canJoin, isFalse);
      await receive('$found\n$initial');
      expect(rooms.battle, isNotNull);
      expect(socket.sink.sent, startCommands);
      expect(controller.canStart, isFalse);
    },
  );
  test(
    'baseline received before account confirmation cannot authorize start',
    () async {
      await session.disconnect();
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect(login: false);
      final pending = auth.login(
        username: 'ExamplePlayer',
        password: 'synthetic',
      );
      await drain();
      await receive(identity);
      await pending;
      expect(controller.canStart, isFalse);
      await receive(baseline);
      expect(controller.canStart, isTrue);
    },
  );

  test('cancel failure is safe and is never retried', () async {
    start();
    final token = controller.state.attemptToken!;
    socket.sink.onSend = (value) {
      if (value == cancelCommand) throw StateError('private-error');
    };
    expect(controller.cancel(token), isFalse);
    await drain();
    expect(controller.state.phase, MatchmakingPhase.disconnected);
    expect(controller.state.notice, MatchmakingNotice.sendFailed);
    expect(controller.cancel(token), isFalse);
    expect(socket.sink.sent, startCommands);
  });

  test('confirmed queue has no response deadline until cancellation', () async {
    start();
    await receive(queued);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller.state.phase, MatchmakingPhase.searching);
    expect(controller.canCancel, isTrue);
    expect(socket.sink.sent, startCommands);
  });

  test(
    'late cancellation is emitted at most once across repeated transitions',
    () async {
      start();
      controller.cancel(controller.state.attemptToken!);
      await receive(queued);
      await receive(baseline);
      await receive(queued);
      await receive(queued);
      expect(socket.sink.sent, [
        ...startCommands,
        cancelCommand,
        cancelCommand,
      ]);
    },
  );

  test(
    'leaving adopted room does not unlock another search in this attempt',
    () async {
      start();
      await receive('$found\n$initial');
      rooms.leave();
      await receive('>$room\n|deinit');
      await receive(baseline);
      expect(controller.canStart, isFalse);
      expect(controller.state.phase, MatchmakingPhase.outcomeUnknown);
    },
  );

  test('controllers from different sessions cannot be composed', () async {
    final other = ShowdownSession();
    final otherCatalog = FormatCatalogController(session: other);
    expect(
      () => MatchmakingController(
        session: session,
        auth: auth,
        catalog: otherCatalog,
        rooms: rooms,
      ),
      throwsArgumentError,
    );
    await otherCatalog.dispose();
    await other.dispose();
  });
}
