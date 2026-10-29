import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_availability.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/features/battle/battle_panel.dart';
import 'package:pokemon_showdown_client/features/connection/connection_screen.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_message_localization.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_panel.dart';
import 'package:pokemon_showdown_client/l10n/app_localizations.dart';

import 'support/matchmaking_ui_harness.dart';

const baseline = '|updatesearch|{"searching":[],"games":null}';
const formats = '|formats|,1|Singles|[Gen 9] Random Battle,4f';
const queued = '|updatesearch|{"searching":["gen9randombattle"],"games":null}';
const found =
    '|updatesearch|{"searching":[],"games":{"battle-gen9randombattle-ui":"Found battle"}}';
const initial =
    '>battle-gen9randombattle-ui\n|init|battle\n|player|p1|ExampleUser\n|player|p2|Other\n|gen|9\n|gametype|singles\n|start';
const commands = ['|/utm null', '|/search gen9randombattle'];
const cancelCommand = '|/cancelsearch gen9randombattle';
Finder control(String id) => find.byKey(Key('matchmaking.$id'));
Finder scrollable() => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> reveal(WidgetTester tester, Finder target) async {
  tester.state<ScrollableState>(scrollable()).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 180, scrollable: scrollable());
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester,
  MatchmakingUiHarness h,
  String language, {
  bool full = false,
  double scale = 1,
  String? font,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        fontFamily: font,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const Key('matchmaking.capture'),
        child: full
            ? ConnectionScreen(
                controller: h.account.connection,
                authController: h.account.auth,
                matchmakingController: h.search,
              )
            : Scaffold(
                body: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      MatchmakingPanel(
                        controller: h.search,
                        onDisconnect: h.account.connection.disconnect,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> receive(
  WidgetTester tester,
  MatchmakingUiHarness h,
  String wire,
) async {
  h.account.socket.incoming.add(wire);
  await tester.pumpAndSettle();
}

Future<void> ready(
  WidgetTester tester,
  MatchmakingUiHarness h, {
  bool login = true,
}) async {
  final pending = h.account.session.connect(
    Uri.parse('wss://sim3.psim.us/showdown/websocket'),
  );
  h.account.socket.handshake.complete();
  await pending;
  await receive(tester, h, '|challstr|0|synthetic-challenge');
  if (login) {
    final auth = h.account.auth.login(
      username: 'ExampleUser',
      password: 'synthetic',
    );
    await tester.pumpAndSettle();
    await receive(tester, h, '|updateuser| ExampleUser|1|1|{}');
    await auth;
  }
  await receive(tester, h, '$formats\n$baseline');
  h.account.socket.sink.sent.clear();
}

Future<void> enable(WidgetTester tester) async {
  await reveal(tester, control('experimental'));
  await tester.tap(control('experimental'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String id) async {
  await reveal(tester, control(id));
  await tester.tap(control(id));
  await tester.pumpAndSettle();
}

bool startEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(control('start')).onPressed != null;
bool cancelEnabled(WidgetTester tester) =>
    tester.widget<OutlinedButton>(control('cancel')).onPressed != null;
Future<void> unmount(
  WidgetTester tester,
  MatchmakingUiHarness h, {
  bool dispose = true,
}) async {
  await tester.pumpWidget(const SizedBox());
  if (dispose) {
    await tester.runAsync(h.dispose);
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets(
      '$language: explicit opt-in, duplicate clicks and uncertain cancellation',
      (tester) async {
        final h = MatchmakingUiHarness();
        addTearDown(h.dispose);
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        await mount(tester, h, language);
        expect(h.account.socket.sink.sent, isEmpty);
        expect(startEnabled(tester), isFalse);
        await ready(tester, h);
        expect(find.text(l10n.matchmakingNeedExperimental), findsOneWidget);
        await enable(tester);
        await reveal(tester, control('start'));
        final callback = tester
            .widget<FilledButton>(control('start'))
            .onPressed!;
        callback();
        callback();
        await tester.pumpAndSettle();
        expect(h.account.socket.sink.sent, commands);
        expect(find.text(l10n.matchmakingSubmitting), findsOneWidget);
        expect(startEnabled(tester), isFalse);
        expect(
          tester.widget<SwitchListTile>(control('experimental')).onChanged,
          isNull,
        );
        await receive(tester, h, queued);
        expect(find.text(l10n.matchmakingSearching), findsOneWidget);
        await reveal(tester, control('cancel'));
        final cancel = tester
            .widget<OutlinedButton>(control('cancel'))
            .onPressed!;
        cancel();
        cancel();
        await tester.pumpAndSettle();
        expect(h.account.socket.sink.sent, [...commands, cancelCommand]);
        expect(find.text(l10n.matchmakingCancelling), findsOneWidget);
        await receive(tester, h, baseline);
        expect(find.text(l10n.matchmakingStoppedObserved), findsOneWidget);
        expect(startEnabled(tester), isFalse);
        expect(cancelEnabled(tester), isFalse);
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(find.text(l10n.matchmakingOutcomeUnknown), findsOneWidget);
        expect(find.text(l10n.matchmakingRecoveryHint), findsOneWidget);
        await tap(tester, 'recover');
        expect(h.account.session.status, TransportStatus.disconnected);
        expect(h.account.socket.sink.sent, [...commands, cancelCommand]);
        await unmount(tester, h);
      },
    );

    testWidgets(
      '$language: account and catalog blockers refresh within unavailable phase',
      (tester) async {
        final h = MatchmakingUiHarness();
        addTearDown(h.dispose);
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        await mount(tester, h, language);
        await ready(tester, h, login: false);
        await enable(tester);
        expect(find.text(l10n.matchmakingNeedAccount), findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(control('experimental')).value,
          isTrue,
        );
        final pending = h.account.auth.login(
          username: 'ExampleUser',
          password: 'synthetic',
        );
        await tester.pumpAndSettle();
        await receive(tester, h, '|updateuser| ExampleUser|1|1|{}');
        await pending;
        await receive(tester, h, '$baseline\n|formats|');
        expect(find.text(l10n.matchmakingNotAdvertised), findsOneWidget);
        await receive(tester, h, '|formats|Broken,zz');
        expect(find.text(l10n.matchmakingMalformedCatalog), findsOneWidget);
        await receive(tester, h, formats);
        expect(startEnabled(tester), isTrue);
        await receive(tester, h, queued);
        expect(find.text(l10n.matchmakingExternalSearch), findsOneWidget);
        expect(startEnabled(tester), isFalse);
        await receive(tester, h, found);
        expect(find.text(l10n.matchmakingExistingGame), findsOneWidget);
        await unmount(tester, h);
      },
    );

    testWidgets(
      '$language: cancelled search opens one battle with first request',
      (tester) async {
        final h = MatchmakingUiHarness();
        addTearDown(h.dispose);
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        await mount(tester, h, language, full: true);
        await ready(tester, h);
        await enable(tester);
        await tap(tester, 'start');
        await tap(tester, 'cancel');
        final data = jsonDecode(
          File('test/fixtures/battle/requests.json').readAsStringSync(),
        );
        final request = (data['cases'] as List).firstWhere(
          (v) => v['id'] == 'move',
        )['payload'];
        request['side']['name'] = 'ExampleUser';
        await receive(
          tester,
          h,
          '$baseline\n$found\n$initial\n|request|${jsonEncode(request)}',
        );
        expect(h.search.state.phase, MatchmakingPhase.inBattle);
        await reveal(tester, control('status'));
        expect(find.text(l10n.matchmakingInBattle), findsOneWidget);
        final battle = h.account.connection.battle!;
        expect(battle.state.requestRevision, 1);
        await reveal(tester, find.byType(BattlePanel));
        expect(
          tester.widget<BattlePanel>(find.byType(BattlePanel)).controller,
          same(battle),
        );
        expect(h.account.socket.sink.sent, [...commands, cancelCommand]);
        await unmount(tester, h);
      },
    );

    testWidgets(
      '$language: large text, narrow screen and keyboard remain scrollable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final h = MatchmakingUiHarness();
        addTearDown(h.dispose);
        await mount(tester, h, language, scale: 2);
        await ready(tester, h);
        await enable(tester);
        await tap(tester, 'start');
        await tap(tester, 'cancel');
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        await reveal(tester, control('recover'));
        expect(tester.takeException(), isNull);
        await unmount(tester, h);
      },
    );
  }

  testWidgets('screen removal preserves app-owned search and can remount it', (
    tester,
  ) async {
    final h = MatchmakingUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'en', full: true);
    await ready(tester, h);
    await enable(tester);
    await tap(tester, 'start');
    await unmount(tester, h, dispose: false);
    await receive(tester, h, queued);
    expect(h.search.state.phase, MatchmakingPhase.searching);
    expect(h.account.session.status, TransportStatus.connected);
    await mount(tester, h, 'en', full: true);
    await reveal(tester, control('cancel'));
    expect(cancelEnabled(tester), isTrue);
    expect(h.account.socket.sink.sent, commands);
    await unmount(tester, h);
  });

  testWidgets(
    'stale start callback cannot act after server information changes',
    (tester) async {
      final h = MatchmakingUiHarness();
      addTearDown(h.dispose);
      await mount(tester, h, 'en');
      await ready(tester, h);
      await enable(tester);
      final callback = tester.widget<FilledButton>(control('start')).onPressed!;
      await receive(tester, h, queued);
      callback();
      await tester.pumpAndSettle();
      expect(h.account.socket.sink.sent, isEmpty);
      expect(startEnabled(tester), isFalse);
      await unmount(tester, h);
    },
  );

  testWidgets('manual join and search reserve the same room owner', (
    tester,
  ) async {
    final h = MatchmakingUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'en');
    await ready(tester, h);
    await enable(tester);
    h.account.connection.join('battle-manual');
    await tester.pumpAndSettle();
    expect(startEnabled(tester), isFalse);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.matchmakingRoomBusy), findsOneWidget);
    expect(h.account.socket.sink.sent, ['|/join battle-manual']);
    await unmount(tester, h);
  });

  testWidgets('server notices are localized, never rendered as raw text', (
    tester,
  ) async {
    final h = MatchmakingUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'en');
    await ready(tester, h);
    await enable(tester);
    await tap(tester, 'start');
    await receive(tester, h, '|popup|private-untrusted-server-text');
    expect(find.textContaining('private-untrusted'), findsNothing);
    expect(h.search.state.phase, MatchmakingPhase.submitting);
    expect(control('notice'), findsOneWidget);
    await unmount(tester, h);
  });

  testWidgets('status is a live region for screen readers', (tester) async {
    final h = MatchmakingUiHarness();
    addTearDown(h.dispose);
    final semantics = tester.ensureSemantics();
    await mount(tester, h, 'en');
    expect(
      tester
          .getSemantics(control('status'))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
    await unmount(tester, h);
  });

  test('all phases, notices and format availability reasons have RU/EN translations', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final phase in MatchmakingPhase.values) {
        expect(localizeMatchmakingPhase(phase, l10n), isNotEmpty);
      }
      for (final notice in MatchmakingNotice.values) {
        expect(localizeMatchmakingNotice(notice, l10n), isNotEmpty);
      }
      for (final reason in FormatAvailability.values) {
        expect(localizeFormatAvailability(reason, l10n), isNotEmpty);
      }
    }
  });

  testWidgets('capture search layouts when requested', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_MATCHMAKING')) return;
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const fontPath = String.fromEnvironment('CAPTURE_FONT');
    if (fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final font = FontLoader('CaptureSearch');
        font.addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        await font.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final h = MatchmakingUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'ru');
    await ready(tester, h);
    for (final language in ['ru', 'en']) {
      await mount(
        tester,
        h,
        language,
        font: fontPath.isEmpty ? null : 'CaptureSearch',
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('matchmaking.capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/showdown-matchmaking-$language.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await unmount(tester, h);
  });
}
