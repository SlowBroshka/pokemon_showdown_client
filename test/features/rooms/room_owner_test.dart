import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/decisions/battle_choice.dart';
import 'package:pokemon_showdown_client/core/matchmaking/search/search_snapshot.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/features/rooms/room_handoff_phase.dart';
import 'package:pokemon_showdown_client/features/rooms/room_owner.dart';

import '../../core/transport/support/fake_socket_channel.dart';

const room = 'battle-gen9randombattle-test';
const baseline = '|updatesearch|{"searching":[],"games":null}';
const identity = '|updateuser| ExamplePlayer|1|1|{}';
String games(List<String> ids) =>
    '|updatesearch|${jsonEncode({
      'searching': [],
      'games': {for (final id in ids) id: 'Example'},
    })}';
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
  final initial =
      '|init|battle\n|title|Found battle\n|gen|9\n|gametype|singles\n|player|p1|ExamplePlayer\n|player|p2|Opponent\n|start\n|turn|1\n|request|${jsonEncode(move)}';
  late FakeSocketChannel socket;
  late List<FakeSocketChannel> sockets;
  late ShowdownSession session;
  late RoomOwner owner;
  Future<void> receive(String wire) async {
    socket.incoming.add(wire);
    await drain();
  }

  Future<void> connect() async {
    final future = session.connect(Uri.parse('wss://example.test'));
    socket.handshake.complete();
    await future;
    await receive('$identity\n$baseline');
  }

  Object reserve() => owner.reserveSearch(
    userId: 'exampleplayer',
    connectionEpoch: session.connectionEpoch,
    baseline: owner.searchBaseline!,
  )!;
  Future<void> adopt() async {
    reserve();
    await receive(games([room]));
    await receive('>$room\n$initial');
  }

  setUp(() async {
    socket = FakeSocketChannel();
    sockets = [socket];
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    owner = RoomOwner(session);
    await connect();
  });
  tearDown(() async {
    owner.dispose();
    await owner.closed;
    await session.dispose();
    for (final s in sockets) {
      await s.incoming.close();
    }
  });

  test(
    'reservation blocks manual join and requires current baseline and identity',
    () {
      expect(
        owner.reserveSearch(
          userId: 'other',
          connectionEpoch: 1,
          baseline: owner.searchBaseline!,
        ),
        isNull,
      );
      expect(
        owner.reserveSearch(
          userId: 'exampleplayer',
          connectionEpoch: 0,
          baseline: owner.searchBaseline!,
        ),
        isNull,
      );
      expect(
        owner.reserveSearch(
          userId: 'exampleplayer',
          connectionEpoch: 1,
          baseline: SearchSnapshot(searching: [], games: null),
        ),
        isNull,
      );
      final token = reserve();
      owner.join('lobby');
      expect(owner.canJoin, isFalse);
      expect(socket.sink.sent, isEmpty);
      expect(
        owner.reserveSearch(
          userId: 'exampleplayer',
          connectionEpoch: 1,
          baseline: owner.searchBaseline!,
        ),
        isNull,
      );
      expect(owner.releaseSearch(Object()), isFalse);
      expect(owner.releaseSearch(token), isTrue);
      final next = reserve();
      expect(owner.releaseSearch(token), isFalse);
      expect(owner.releaseSearch(next), isTrue);
    },
  );

  for (final first in [true, false]) {
    test(
      'adopts exactly once with games first=$first and first-frame request',
      () async {
        reserve();
        await receive(first ? games([room]) : '>$room\n$initial');
        expect(owner.battle, isNull);
        await receive(first ? '>$room\n$initial' : games([room]));
        final battle = owner.battle!;
        expect(owner.handoffPhase, RoomHandoffPhase.adopted);
        expect(owner.room!.title, 'Found battle');
        expect(battle.state.requestRevision, 1);
        expect(battle.canChoose, isTrue);
        expect(socket.sink.sent, isEmpty);
        await receive('>$room\n|init|battle');
        expect(owner.battle, same(battle));
        expect(battle.state.requestRevision, 1);
        expect(
          battle.submit(battle.capture(const BattleChoice.move(1))!),
          isTrue,
        );
        expect(socket.sink.sent, ['$room|/choose move 1|7']);
      },
    );
  }
  test('games and init/request in one frame do not lose events', () async {
    reserve();
    await receive('${games([room])}\n>$room\n$initial');
    expect(owner.battle!.state.requestRevision, 1);
    expect(owner.battle!.canChoose, isTrue);
  });
  test(
    'empty search during handoff does not release reservation or leave match',
    () async {
      reserve();
      await receive(baseline);
      await receive(games([room]));
      await receive('>$room\n$initial');
      expect(owner.handoffPhase, RoomHandoffPhase.adopted);
      expect(socket.sink.sent, isEmpty);
    },
  );
  test('no adoption with spectator identity or missing games', () async {
    reserve();
    await receive(games([room]));
    await receive('>$room\n|init|battle\n|player|p1|SomeoneElse');
    expect(owner.battle, isNull);
    expect(owner.handoffPhase, RoomHandoffPhase.awaitingEvidence);
  });
  test('conflicting private side fails before admission', () async {
    reserve();
    final wrong = jsonDecode(jsonEncode(move)) as Map<String, dynamic>;
    wrong['side']['name'] = 'Other';
    await receive('>$room\n|init|battle\n|request|${jsonEncode(wrong)}');
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    await receive(games([room]));
    await receive('>$room\n$initial');
    expect(owner.battle, isNull);
    expect(socket.sink.sent, isEmpty);
  });
  test('second candidate fails and never selects either arbitrarily', () async {
    reserve();
    await receive('>$room\n|init|battle');
    await receive('>battle-other\n|init|battle');
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(owner.battle, isNull);
    expect(socket.sink.sent, isEmpty);
  });
  test('multiple games and non-battle games fail explicitly', () async {
    reserve();
    await receive(games([room, 'mafia']));
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(owner.room, isNull);
  });
  test(
    'second game cannot replace active battle; captured decisions revoked',
    () async {
      await adopt();
      final battle = owner.battle!;
      final choice = battle.capture(const BattleChoice.move(1))!;
      await receive(games([room, 'battle-other']));
      expect(owner.battle, same(battle));
      expect(owner.room!.id, room);
      expect(battle.submit(choice), isFalse);
      expect(socket.sink.sent, isEmpty);
    },
  );
  test('identity change revokes pending admission', () async {
    reserve();
    await receive('>$room\n|init|battle');
    await receive('|updateuser| Other|1|1|{}');
    await receive(games([room]));
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(owner.battle, isNull);
  });
  test('malformed search evidence does not authorize admission', () async {
    reserve();
    await receive('|updatesearch|{');
    await receive('>$room\n$initial');
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(owner.battle, isNull);
  });
  test('buffer event limit accepts 256 but rejects 257', () async {
    reserve();
    await receive(
      '>$room\n|init|battle\n${List.filled(255, '|turn|1').join('\n')}',
    );
    expect(owner.handoffPhase, RoomHandoffPhase.awaitingEvidence);
    await receive('>$room\n|turn|2');
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(owner.battle, isNull);
  });
  test('UTF8 byte limit cannot be bypassed by non-ASCII text', () async {
    reserve();
    await receive('>$room\n|init|battle');
    await receive('>$room\n|message|${List.filled(131072, 'я').join()}');
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(owner.battle, isNull);
  });
  test('timeout is outcomeUnknown and late evidence cannot admit', () async {
    owner.dispose();
    await owner.closed;
    owner = RoomOwner(
      session,
      handoffTimeout: const Duration(milliseconds: 20),
    );
    await receive('$identity\n$baseline');
    reserve();
    await receive('>$room\n|init|battle');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    await receive(games([room]));
    expect(owner.battle, isNull);
  });
  test(
    'disconnect clears candidate; new connection rejects stale token/baseline',
    () async {
      final oldBaseline = owner.searchBaseline!;
      final token = reserve();
      await receive('>$room\n$initial');
      await session.disconnect();
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect();
      expect(owner.releaseSearch(token), isFalse);
      expect(
        owner.reserveSearch(
          userId: 'exampleplayer',
          connectionEpoch: 1,
          baseline: oldBaseline,
        ),
        isNull,
      );
      expect(owner.battle, isNull);
      expect(owner.handoffPhase, RoomHandoffPhase.idle);
      reserve();
      await receive(games([room]));
      await receive('>$room\n$initial');
      expect(owner.battle!.state.connectionEpoch, 2);
    },
  );
  test(
    'unsupported mechanic blocks battle choices without restarting search',
    () async {
      await adopt();
      await receive('>$room\n|-transform|p1a: Alpha|p2a: Other');
      expect(owner.handoffPhase, RoomHandoffPhase.adopted);
      expect(owner.battle!.canChoose, isFalse);
      expect(socket.sink.sent, isEmpty);
    },
  );
  test(
    'dispose cancels candidate and leaves caller-owned session alive',
    () async {
      reserve();
      await receive('>$room\n|init|battle');
      owner.dispose();
      await owner.closed;
      await receive(games([room]));
      expect(owner.battle, isNull);
      expect(session.status, TransportStatus.connected);
      expect(socket.sink.sent, isEmpty);
    },
  );
  test('pending manual join prevents search reservation', () {
    owner.join('battle-manual');
    expect(
      owner.reserveSearch(
        userId: 'exampleplayer',
        connectionEpoch: 1,
        baseline: owner.searchBaseline!,
      ),
      isNull,
    );
    expect(socket.sink.sent, ['|/join battle-manual']);
  });

  test('changed own player after admission revokes captured choice', () async {
    await adopt();
    final battle = owner.battle!;
    final choice = battle.capture(const BattleChoice.move(1))!;
    await receive('>$room\n|player|p1|Other');
    expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
    expect(battle.submit(choice), isFalse);
  });

  test(
    'unowned second init never sends leave or replaces active room',
    () async {
      await adopt();
      final battle = owner.battle;
      await receive('>battle-other\n|init|battle');
      expect(owner.battle, same(battle));
      expect(owner.handoffPhase, RoomHandoffPhase.outcomeUnknown);
      expect(socket.sink.sent, isEmpty);
    },
  );
  test('named private request proves side before public player arrives', () async {
    reserve();
    await receive(games([room]));
    await receive(
      '>$room\n|init|battle\n|gen|9\n|gametype|singles\n|start\n|request|${jsonEncode(move)}',
    );
    expect(owner.handoffPhase, RoomHandoffPhase.adopted);
    expect(owner.battle!.state.requestRevision, 1);
    await receive('>$room\n|request|${jsonEncode(move)}');
    expect(owner.handoffPhase, RoomHandoffPhase.adopted);
    expect(owner.battle!.state.requestRevision, 2);
  });
}
