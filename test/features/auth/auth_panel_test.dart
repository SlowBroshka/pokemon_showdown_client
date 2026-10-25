import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pokemon_showdown_client/core/auth/auth_controller.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/features/auth/auth_message_localization.dart';
import 'package:pokemon_showdown_client/features/connection/connection_screen.dart';
import 'package:pokemon_showdown_client/l10n/app_localizations.dart';

import 'support/auth_ui_harness.dart';

Finder verticalScroll() => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);
Finder field(String key) => find.byKey(Key('auth.$key'));

Future<void> reveal(WidgetTester tester, Finder finder) async {
  tester.state<ScrollableState>(verticalScroll().first).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: verticalScroll().first,
  );
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester,
  AuthUiHarness h,
  String language, {
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
        inputDecorationTheme: const InputDecorationTheme(filled: true),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const Key('auth.capture'),
        child: ConnectionScreen(
          controller: h.connection,
          authController: h.auth,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> connect(WidgetTester tester, AuthUiHarness h) async {
  final pending = h.session.connect(
    Uri.parse('wss://sim3.psim.us/showdown/websocket'),
  );
  h.socket.handshake.complete();
  await pending;
  h.socket.incoming.add('|challstr|0|synthetic-challenge');
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String password = ' private-password+&= ',
}) async {
  await reveal(tester, field('username'));
  await tester.enterText(field('username'), 'ExampleUser');
  await reveal(tester, field('password'));
  await tester.enterText(field('password'), password);
}

Future<void> submit(WidgetTester tester) async {
  await reveal(tester, field('submit'));
  await tester.tap(field('submit'));
  await tester.pumpAndSettle();
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets(
      '$language: full connect, sign in, confirm, room, leave and sign out flow',
      (tester) async {
        final h = AuthUiHarness();
        addTearDown(h.dispose);
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        await mount(tester, h, language);
        await tester.tap(find.text(l10n.connect));
        await tester.pump();
        h.socket.handshake.complete();
        h.socket.incoming.add('|challstr|0|synthetic-challenge');
        await tester.pumpAndSettle();
        await fill(tester);
        expect(tester.widget<TextField>(field('password')).obscureText, isTrue);
        await tester.tap(field('togglePassword'));
        await tester.pump();
        expect(
          tester.widget<TextField>(field('password')).obscureText,
          isFalse,
        );
        await submit(tester);
        expect(h.auth.state.phase, AuthPhase.awaitingConfirmation);
        expect(h.clients, hasLength(1));
        expect(
          (h.clients.single.requests.single as http.Request).bodyFields['pass'],
          ' private-password+&= ',
        );
        await reveal(tester, field('password'));
        expect(
          tester.widget<TextField>(field('password')).controller!.text,
          isEmpty,
        );
        expect(tester.widget<TextField>(field('password')).obscureText, isTrue);
        expect(find.text(l10n.authSignedIn('ExampleUser')), findsNothing);
        h.socket.incoming.add('|updateuser| ExampleUser|1|1|{}');
        await tester.pumpAndSettle();
        await reveal(tester, field('signOut'));
        expect(find.text(l10n.authSignedIn('ExampleUser')), findsOneWidget);
        expect(field('password'), findsNothing);
        final room = find.widgetWithText(TextField, l10n.roomIdLabel);
        await reveal(tester, room);
        await tester.enterText(room, 'one');
        await tester.tap(find.text(l10n.join));
        await tester.pumpAndSettle();
        h.socket.incoming.add('>one\n|init|chat\n|title|Example room');
        await tester.pumpAndSettle();
        await reveal(tester, find.text(l10n.leaveRoom));
        await tester.tap(find.text(l10n.leaveRoom));
        h.socket.incoming.add('>one\n|deinit');
        await tester.pumpAndSettle();
        await reveal(tester, field('signOut'));
        await tester.tap(field('signOut'));
        await tester.pumpAndSettle();
        expect(h.session.status, TransportStatus.disconnected);
        expect(h.auth.state.username, isNull);
        expect(h.socket.sink.sent, [
          '|/trn ExampleUser,0,synthetic,exampleuser,2,0,example.invalid;not-a-signature',
          '|/join one',
          'one|/leave',
        ]);
        await reveal(tester, field('password'));
        expect(
          tester.widget<TextField>(field('password')).controller!.text,
          isEmpty,
        );
        expect(tester.widget<TextField>(field('password')).enabled, isFalse);
        await unmount(tester);
      },
    );

    testWidgets(
      '$language: HTTP error is localized and a retry needs a fresh password',
      (tester) async {
        final h = AuthUiHarness();
        addTearDown(h.dispose);
        h.respond = (_) => http.StreamedResponse(
          Stream.value(
            utf8.encode(']{"error":"<script>private-server-text</script>"}'),
          ),
          200,
        );
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        await mount(tester, h, language);
        await connect(tester, h);
        await fill(tester);
        await submit(tester);
        await reveal(tester, find.text(l10n.authLoginRejected));
        expect(find.textContaining('private-server-text'), findsNothing);
        expect(h.socket.sink.sent, isEmpty);
        expect(tester.widget<FilledButton>(field('submit')).onPressed, isNull);
        h.respond = (_) => AuthUiHarness.success();
        await fill(tester);
        await submit(tester);
        expect(h.clients, hasLength(2));
        expect(h.auth.state.phase, AuthPhase.awaitingConfirmation);
        await reveal(tester, field('cancel'));
        await tester.tap(field('cancel'));
        await tester.pumpAndSettle();
        expect(h.session.status, TransportStatus.disconnected);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'cancel during HTTP keeps the connection; stale HTTP cannot confirm',
    (tester) async {
      final h = AuthUiHarness();
      addTearDown(h.dispose);
      final delayed = Completer<http.StreamedResponse>();
      h.respond = (_) => delayed.future;
      await mount(tester, h, 'ru');
      await connect(tester, h);
      await fill(tester);
      await submit(tester);
      expect(tester.widget<FilledButton>(field('submit')).onPressed, isNull);
      await reveal(tester, field('cancel'));
      await tester.tap(field('cancel'));
      await tester.pumpAndSettle();
      delayed.complete(AuthUiHarness.success());
      await tester.pumpAndSettle();
      expect(h.auth.state.error, AuthFailure.cancelled);
      expect(h.session.status, TransportStatus.connected);
      expect(h.socket.sink.sent, isEmpty);
      await reveal(tester, field('password'));
      expect(
        tester.widget<TextField>(field('password')).controller!.text,
        isEmpty,
      );
      await unmount(tester);
    },
  );

  testWidgets('disconnect clears an unsubmitted visible password', (
    tester,
  ) async {
    final h = AuthUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'en');
    await connect(tester, h);
    await fill(tester);
    await tester.tap(field('togglePassword'));
    await tester.pump();
    await h.session.disconnect();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('password')).controller!.text,
      isEmpty,
    );
    expect(tester.widget<TextField>(field('password')).obscureText, isTrue);
    await unmount(tester);
  });

  testWidgets('unsupported server disables credentials and sends no HTTP', (
    tester,
  ) async {
    final h = AuthUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'ru');
    final pending = h.session.connect(Uri.parse('wss://example.test'));
    h.socket.handshake.complete();
    await pending;
    await tester.pumpAndSettle();
    await reveal(tester, field('password'));
    expect(tester.widget<TextField>(field('password')).enabled, isFalse);
    expect(tester.widget<FilledButton>(field('submit')).onPressed, isNull);
    expect(h.clients, isEmpty);
    await unmount(tester);
  });

  for (final language in ['ru', 'en']) {
    testWidgets(
      '$language: narrow layout with large text and keyboard is scrollable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final h = AuthUiHarness();
        addTearDown(h.dispose);
        await mount(tester, h, language, scale: 2);
        await connect(tester, h);
        await fill(tester);
        await reveal(tester, field('submit'));
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }

  test(
    'all auth phases and failures have translations in both languages',
    () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        for (final phase in AuthPhase.values) {
          expect(
            localizeAuthPhase(AuthState(phase, username: 'ExampleUser'), l10n),
            isNotEmpty,
          );
        }
        for (final failure in AuthFailure.values) {
          expect(localizeAuthFailure(failure, l10n), isNotEmpty);
        }
      }
    },
  );

  testWidgets('repeated taps cannot submit twice while HTTP is pending', (
    tester,
  ) async {
    final h = AuthUiHarness();
    addTearDown(h.dispose);
    final delayed = Completer<http.StreamedResponse>();
    h.respond = (_) => delayed.future;
    await mount(tester, h, 'en');
    await connect(tester, h);
    await fill(tester);
    await reveal(tester, field('submit'));
    await tester.tap(field('submit'));
    await tester.tap(field('submit'));
    await tester.pumpAndSettle();
    expect(h.clients, hasLength(1));
    await reveal(tester, field('cancel'));
    await tester.tap(field('cancel'));
    await tester.pumpAndSettle();
    delayed.complete(AuthUiHarness.success());
    await tester.pumpAndSettle();
    expect(h.socket.sink.sent, isEmpty);
    await unmount(tester);
  });

  testWidgets('keyboard submit respects empty username validation', (
    tester,
  ) async {
    final h = AuthUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'en');
    await connect(tester, h);
    await fill(tester);
    await reveal(tester, field('username'));
    await tester.enterText(field('username'), '   ');
    await reveal(tester, field('password'));
    await tester.tap(field('password'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.clients, isEmpty);
    expect(tester.widget<FilledButton>(field('submit')).onPressed, isNull);
    await unmount(tester);
  });

  testWidgets('game-server rejection is localized and clears the identity', (
    tester,
  ) async {
    final h = AuthUiHarness();
    addTearDown(h.dispose);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await mount(tester, h, 'en');
    await connect(tester, h);
    await fill(tester);
    await submit(tester);
    h.socket.incoming.add('|nametaken||private-server-rejection');
    await tester.pumpAndSettle();
    await reveal(tester, find.text(l10n.authIdentityRejected));
    expect(find.textContaining('private-server-rejection'), findsNothing);
    expect(h.auth.state.username, isNull);
    expect(h.session.status, TransportStatus.disconnected);
    expect(h.clients, hasLength(1));
    await unmount(tester);
  });

  testWidgets('capture account layout when requested', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_AUTH')) return;
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const path = String.fromEnvironment('CAPTURE_FONT');
    if (path.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('CaptureAuth');
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final h = AuthUiHarness();
    addTearDown(h.dispose);
    await mount(tester, h, 'ru', font: path.isEmpty ? null : 'CaptureAuth');
    await connect(tester, h);
    await reveal(tester, field('submit'));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('auth.capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/showdown-auth-ui.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await unmount(tester);
  });
}
