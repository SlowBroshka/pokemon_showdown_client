import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/features/battle/battle_panel.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';
import 'package:pokemon_showdown_client/l10n/app_localizations.dart';

import '../../core/transport/support/fake_socket_channel.dart';

void main() {
  final cases =
      (jsonDecode(File('test/fixtures/battle/requests.json').readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List;
  String request(String id) {
    final c = cases.cast<Map<String, dynamic>>().firstWhere(
      (c) => c['id'] == id,
    );
    return '|request|${c.containsKey('rawPayload') ? c['rawPayload'] : jsonEncode(c['payload'])}';
  }

  for (final locale in ['ru', 'en']) {
    testWidgets('$locale: moves, errors, switch, tera, wait, result', (
      tester,
    ) async {
      final socket = FakeSocketChannel();
      final session = ShowdownSession(
        transport: ShowdownTransport(channelFactory: (_) => socket),
      );
      final owner = ConnectionController(session: session);
      addTearDown(() async {
        owner.dispose();
        await owner.closed;
        await session.dispose();
        await socket.incoming.close();
      });
      final pending = owner.connect('wss://example.test');
      socket.handshake.complete();
      await tester.pump();
      await pending;
      owner.join('battle-ui');
      Future<void> receive(String lines) async {
        socket.incoming.add('>battle-ui\n$lines');
        await tester.pumpAndSettle();
      }

      await receive(
        '|init|battle\n|player|p1|ExamplePlayer\n|player|p2|OtherPlayer\n|gen|9\n|gametype|singles\n|start\n|turn|1\n|switch|p1a: Alpha|Pikachu, L80|200/200\n|switch|p2a: Opponent|Snorlax, L80|100/100\n${request('move')}',
      );
      final l = await AppLocalizations.delegate.load(Locale(locale));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: SingleChildScrollView(
                child: BattlePanel(controller: owner.battle!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String key) async {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      VoidCallback? action(String key) =>
          tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed;
      expect(find.text(l.battlePublicHp(100, '100')), findsOneWidget);
      expect(action('battle.switch.1'), isNull);
      final old = action('battle.move.1')!;
      old();
      old();
      await tester.pumpAndSettle();
      expect(socket.sink.sent.last, 'battle-ui|/choose move 1|7');
      expect(socket.sink.sent, hasLength(2));
      expect(find.text(l.battleSubmitted), findsOneWidget);
      expect(action('battle.move.1'), isNull);
      await receive('|error|[Invalid choice] private server message');
      expect(find.text(l.battleRejected), findsOneWidget);
      expect(find.textContaining('private server message'), findsNothing);
      await tap('battle.switch.2');
      expect(socket.sink.sent.last, 'battle-ui|/choose switch 2|7');
      await receive('|error|[Unavailable choice] Synthetic unavailable');
      expect(find.text(l.battleUnavailable), findsOneWidget);
      expect(action('battle.move.1'), isNull);
      await receive(request('tera'));
      await tap('battle.tera');
      final stale = action('battle.move.1')!;
      await receive(request('tera'));
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('battle.tera')))
            .value,
        isFalse,
      );
      final count = socket.sink.sent.length;
      stale();
      expect(socket.sink.sent, hasLength(count));
      await tap('battle.tera');
      await tap('battle.move.1');
      expect(
        socket.sink.sent.last.toString(),
        contains('move 1 terastallize|'),
      );
      await receive(request('force-switch'));
      expect(find.text(l.battleForced), findsOneWidget);
      expect(find.byKey(const Key('battle.move.1')), findsNothing);
      await tap('battle.switch.2');
      await receive(request('wait'));
      expect(find.text(l.battleWaiting), findsOneWidget);
      await receive(request('clear'));
      expect(find.text(l.battleWaiting), findsOneWidget);
      await receive(
        '${request('move')}\n|-damage|p2a: Opponent|50/100 par\n|move|p1a: Alpha|Thunderbolt|p2a: Opponent',
      );
      expect(find.text(l.battlePublicHp(50, '100')), findsOneWidget);
      expect(find.text(l.battleStatus('par')), findsOneWidget);
      for (final id in ['broken-json', 'doubles']) {
        await receive(request(id));
        expect(owner.battle!.canChoose, isFalse);
      }
      await receive('${request('move')}\n|win|ExamplePlayer');
      expect(find.text(l.battleWinner('ExamplePlayer')), findsOneWidget);
      expect(find.byKey(const Key('battle.move.1')), findsNothing);
      await receive('|deinit');
      expect(find.text(l.battleWinner('ExamplePlayer')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('narrow large-text panel, unsupported state and stale result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = FakeSocketChannel();
    final session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    final owner = ConnectionController(session: session);
    addTearDown(() async {
      owner.dispose();
      await owner.closed;
      await session.dispose();
      await socket.incoming.close();
    });
    final pending = owner.connect('wss://example.test');
    socket.handshake.complete();
    await tester.pump();
    await pending;
    owner.join('battle-ui');
    socket.incoming.add(
      '>battle-ui\n|init|battle\n|gen|9\n|gametype|singles\n|start\n${request('tera')}',
    );
    await tester.pumpAndSettle();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(
              key: key,
              child: SingleChildScrollView(
                child: BattlePanel(controller: owner.battle!),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('battle.move.1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    const capture = String.fromEnvironment('BATTLE_CAPTURE');
    if (capture.isNotEmpty) {
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(capture).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    socket.incoming.add('>battle-ui\n|-boost|p1a: Alpha|atk|1');
    await tester.pumpAndSettle();
    expect(owner.battle!.canChoose, isFalse);
    socket.incoming.add('>battle-ui\n|tie');
    await tester.pumpAndSettle();
    final disconnect = owner.disconnect();
    await tester.pumpAndSettle();
    await disconnect;
    final l = await AppLocalizations.delegate.load(const Locale('ru'));
    expect(find.text(l.staleRoom), findsOneWidget);
    expect(find.text(l.battleTie), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
