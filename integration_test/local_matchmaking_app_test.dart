import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pokemon_showdown_client/features/connection/connection_screen.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';
import 'package:pokemon_showdown_client/features/battle/battle_panel.dart';
import 'package:pokemon_showdown_client/l10n/app_localizations.dart';

import '../test/support/local_matchmaking_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('full local server: UI search opens the matched battle', (
    tester,
  ) async {
    final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
    final suffix = Platform.isAndroid ? 'Android' : 'Linux';
    final a = LocalMatchmakingClient('Ui${suffix}A$nonce');
    final b = LocalMatchmakingClient('Ui${suffix}B$nonce');
    a.search.experimentalEnabled = false;
    final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConnectionScreen(
          controller: a.connection,
          authController: a.auth,
          matchmakingController: a.search,
        ),
      ),
    );
    Future<void> reveal(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    try {
      await a.connect(host: host);
      await b.connect(host: host);
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('matchmaking.experimental'));
      await reveal(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(a.search.experimentalEnabled, isTrue);
      await until(() => a.search.canStart, label: 'UI ready');
      final start = find.byKey(const Key('matchmaking.start'));
      await reveal(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(a.sent, ['|/utm null', '|/search gen9randombattle']);
      await until(
        () => a.search.state.phase == MatchmakingPhase.searching,
        label: 'UI queue',
      );
      b.start();
      await until(
        () =>
            a.search.state.phase == MatchmakingPhase.inBattle && a.requests > 0,
        label: 'UI matched battle',
      );
      await tester.pumpAndSettle();
      await reveal(find.byType(BattlePanel));
      expect(a.connection.room!.id, b.connection.room!.id);
      expect(a.connection.battle!.state.requestRevision, a.requests);
      expect(find.byType(BattlePanel), findsOneWidget);
      expect(a.sent, ['|/utm null', '|/search gen9randombattle']);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await a.close();
      await b.close();
    }
  }, skip: !const bool.fromEnvironment('SHOWDOWN_MATCHMAKING_TEST'));
}
