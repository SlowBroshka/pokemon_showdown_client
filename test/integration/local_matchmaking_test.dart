import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';

import '../support/local_matchmaking_client.dart';

void main() {
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  const enabled = bool.fromEnvironment('SHOWDOWN_MATCHMAKING_TEST');
  test(
    'full server: two clients find one battle and receive private requests',
    () async {
      final a = LocalMatchmakingClient('Alpha$nonce');
      final b = LocalMatchmakingClient('Beta$nonce');
      try {
        await a.connect();
        await b.connect();
        expect(a.search.canStart, isTrue);
        expect(b.search.canStart, isTrue);
        a.start();
        await until(
          () => a.search.state.phase == MatchmakingPhase.searching,
          label: 'first queue',
        );
        b.start();
        await until(
          () => a.connection.battle != null && b.connection.battle != null,
          label: 'matched rooms',
        );
        await until(
          () => a.requests > 0 && b.requests > 0,
          label: 'private requests',
        );
        expect(a.connection.room!.id, b.connection.room!.id);
        expect(a.search.state.phase, MatchmakingPhase.inBattle);
        expect(b.search.state.phase, MatchmakingPhase.inBattle);
        expect(a.connection.battle!.state.requestRevision, a.requests);
        expect(b.connection.battle!.state.requestRevision, b.requests);
        expect(a.search.canStart, isFalse);
        expect(a.sent, ['|/utm null', '|/search gen9randombattle']);
        expect(b.sent, ['|/utm null', '|/search gen9randombattle']);
        expect(
          a.events,
          containsAllInOrder(['queued', 'empty', 'init', 'request']),
        );
        expect(a.events, contains('games'));
        await a.session.disconnect();
        await a.connect();
        expect(a.connection.rooms.searchBaseline!.games, isNotEmpty);
        expect(a.search.canStart, isFalse);
      } finally {
        await a.close();
        await b.close();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'full server: early cancel is followed by one late-queue cancellation',
    () async {
      final a = LocalMatchmakingClient('Delay$nonce');
      try {
        await a.connect();
        final beforeCancel = a.searchUpdates;
        a.start();
        expect(a.search.cancel(a.search.state.attemptToken!), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          a.searchUpdates,
          beforeCancel,
          reason: 'Absent queue cancellation has no ACK',
        );
        await until(
          () => a.searchUpdates >= 3,
          label: 'late queue then cancellation',
        );
        await until(
          () => a.search.state.phase == MatchmakingPhase.stoppedObserved,
          label: 'queue absent',
        );
        expect(a.connection.rooms.searchBaseline!.searching, isEmpty);
        expect(a.events, containsAllInOrder(['queued', 'empty']));
        expect(
          a.sent.where((s) => s == '|/cancelsearch gen9randombattle'),
          hasLength(2),
        );
        expect(a.search.canStart, isFalse);
        await until(
          () => a.search.state.phase == MatchmakingPhase.outcomeUnknown,
          label: 'unconfirmed cancellation timeout',
        );
        await a.session.disconnect();
        await a.connect();
        expect(a.search.canStart, isTrue);
        a.start();
        await until(() => a.search.state.phase == MatchmakingPhase.searching);
        expect(a.search.cancel(a.search.state.attemptToken!), isTrue);
        await until(() => a.connection.rooms.searchBaseline!.searching.isEmpty);
      } finally {
        await a.close();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'full server: another connection observes the same account queue and its cancellation',
    () async {
      final a = LocalMatchmakingClient('Shared$nonce');
      final b = LocalMatchmakingClient('Shared$nonce');
      try {
        await a.connect();
        a.start();
        await until(() => a.search.state.phase == MatchmakingPhase.searching);
        await b.connect();
        expect(
          b.connection.rooms.searchBaseline!.searching,
          contains('gen9randombattle'),
        );
        expect(b.search.canStart, isFalse);
        expect(b.search.canCancel, isFalse);
        expect(a.search.cancel(a.search.state.attemptToken!), isTrue);
        await until(() => b.connection.rooms.searchBaseline!.searching.isEmpty);
        expect(a.search.canStart, isFalse);
      } finally {
        await a.close();
        await b.close();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
