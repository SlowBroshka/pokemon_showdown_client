import 'dart:io';

import 'package:pokemon_showdown_client/l10n/app_localizations.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';
import 'package:pokemon_showdown_client/features/connection/connection_screen.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';

import '../../core/transport/support/fake_socket_channel.dart';

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets(
      '$language: connect, join, display one room and wait for leave confirmation',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        final socket = FakeSocketChannel();
        final session = ShowdownSession(
          transport: ShowdownTransport(channelFactory: (_) => socket),
        );
        final controller = ConnectionController(session: session);
        addTearDown(() async {
          controller.dispose();
          await controller.closed;
          await session.dispose();
          await socket.incoming.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConnectionScreen(controller: controller),
          ),
        );
        await tester.tap(find.text(l10n.connect));
        await tester.pump();
        expect(find.text(l10n.cancel), findsOneWidget);
        socket.handshake.complete();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, l10n.roomIdLabel),
          'one',
        );
        await tester.tap(find.text(l10n.join));
        await tester.pump();
        expect(find.text(l10n.awaitingJoin), findsOneWidget);
        expect(socket.sink.sent, ['|/join one']);
        socket.incoming.add('>one\n|init|chat\n|title|Комната проверки');
        await tester.pumpAndSettle();
        expect(find.text('Комната проверки'), findsOneWidget);
        expect(find.widgetWithText(TextField, l10n.roomIdLabel), findsNothing);
        await tester.tap(find.text(l10n.leaveRoom));
        await tester.pump();
        expect(find.text(l10n.awaitingLeave), findsOneWidget);
        socket.incoming.add('>one\n|deinit');
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextField, l10n.roomIdLabel),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        expect(session.status, TransportStatus.connected);
        expect(controller.canJoin, isTrue);
      },
    );
  }
  testWidgets(
    'small screen and large text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const ConnectionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Уведомления'),
        300,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(find.text('Уведомления'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('connection error is visible without exposing input secrets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConnectionScreen(),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Адрес сервера (WSS)'),
      'wss://user:secret@example.test',
    );
    await tester.tap(find.text('Подключиться'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Введите WSS-адрес'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('capture mobile layout when requested', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    const fontPath = String.fromEnvironment('CAPTURE_FONT');
    if (fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('Preview');
        loader.addFont(
          File(fontPath)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      });
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: fontPath.isEmpty ? null : ThemeData(fontFamily: 'Preview'),
          home: const ConnectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_SCREEN')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/showdown-connection.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
