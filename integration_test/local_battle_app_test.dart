import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';
import 'package:pokemon_showdown_client/features/connection/connection_screen.dart';
import 'package:pokemon_showdown_client/l10n/app_localizations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local engine through the real app UI', (tester) async {
    final session = ShowdownSession();
    final owner = ConnectionController(session: session);
    final l = await AppLocalizations.delegate.load(const Locale('ru'));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionScreen(controller: owner),
        ),
      ),
    );
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (ready()) return;
        if (owner.battle?.state.unsupported == true) fail('Unsupported state');
      }
      fail('UI wait timed out: ${owner.status}, ${owner.battle?.phase}');
    }

    Future<void> reveal(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder finder) async {
      await reveal(finder);
      await tester.tap(finder);
      await tester.pump();
    }

    try {
      final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
      await tester.enterText(
        find.widgetWithText(TextField, l.serverAddress),
        'ws://$host:8000/showdown/websocket',
      );
      await tap(find.text(l.connect));
      await waitFor(() => owner.status == TransportStatus.connected);
      final room = find.widgetWithText(TextField, l.roomIdLabel);
      await reveal(room);
      await tester.enterText(room, 'battle-local');
      await tap(find.text(l.join));
      await waitFor(() => owner.battle?.canChoose == true);
      final battle = owner.battle!;
      Future<void> choose(String key) async {
        final revision = battle.state.requestRevision;
        await tap(find.byKey(Key(key)));
        await waitFor(
          () =>
              battle.choiceRejected ||
              battle.state.requestRevision > revision ||
              battle.state.terminal,
        );
        await waitFor(() => battle.canChoose || battle.state.terminal);
      }

      await choose('battle.move.1');
      expect(battle.choiceRejected, isTrue);
      await choose('battle.switch.2');
      await tap(find.byKey(const Key('battle.tera')));
      await choose('battle.move.1');
      for (var i = 0; i < 120 && !battle.state.terminal; i++) {
        await choose('battle.move.1');
      }
      expect(battle.state.result?.winner, 'LocalPlayer');
      await reveal(find.text(l.battleWinner('LocalPlayer')));
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('${Directory.systemTemp.path}/battle-app-result.png');
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('Battle screenshot: ${output.path}');
      await owner.disconnect();
      await waitFor(() => battle.state.stale);
      expect(battle.canChoose, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
      await owner.closed;
      await session.dispose();
    }
  }, skip: !const bool.fromEnvironment('SHOWDOWN_LIVE'));
}
