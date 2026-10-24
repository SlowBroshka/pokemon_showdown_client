import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';
import 'package:pokemon_showdown_client/features/connection/connection_screen.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../../core/transport/support/fake_socket_channel.dart';

void main() {
  testWidgets(
    'connect, join, display one room and wait for leave confirmation',
    (tester) async {
      final socket = FakeSocketChannel();
      final controller = ConnectionController(
        transport: ShowdownTransport(channelFactory: (_) => socket),
      );
      addTearDown(() async {
        controller.dispose();
        await controller.closed;
        await socket.incoming.close();
      });
      await tester.pumpWidget(
        MaterialApp(home: ConnectionScreen(controller: controller)),
      );
      await tester.tap(find.text('Подключиться'));
      await tester.pump();
      expect(find.text('Отменить'), findsOneWidget);
      socket.handshake.complete();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'ID комнаты'),
        'one',
      );
      await tester.tap(find.text('Войти'));
      await tester.pump();
      expect(find.text('Ожидаем подтверждение входа…'), findsOneWidget);
      expect(socket.sink.sent, ['|/join one']);
      socket.incoming.add('>one\n|init|chat\n|title|Комната проверки');
      await tester.pumpAndSettle();
      expect(find.text('Комната проверки'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ID комнаты'), findsNothing);
      await tester.tap(find.text('Выйти из комнаты'));
      await tester.pump();
      expect(find.text('Ожидаем подтверждение выхода…'), findsOneWidget);
      socket.incoming.add('>one\n|deinit');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'ID комнаты'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small screen and large text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
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
    await tester.pumpWidget(const MaterialApp(home: ConnectionScreen()));
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
