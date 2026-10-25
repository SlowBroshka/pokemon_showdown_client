import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/rooms/room_router.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../transport/support/fake_socket_channel.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSocketChannel socket;
  late ShowdownTransport transport;
  late RoomRouter router;

  setUp(() async {
    socket = FakeSocketChannel();
    transport = ShowdownTransport(channelFactory: (_) => socket);
    router = RoomRouter(transport);
    final connecting = transport.connect(Uri.parse('wss://example.test'));
    socket.handshake.complete();
    await connecting;
    await flush();
  });
  tearDown(() async {
    await router.dispose();
    await transport.dispose();
    await socket.incoming.close();
  });

  Future<void> receive(String message) async {
    socket.incoming.add(message);
    await flush();
  }

  test('routes globals and independent rooms in original order', () async {
    final global = <ServerEvent>[];
    final room = <RoomEvent>[];
    final first = <RoomEvent>[];
    router.globalEvents.listen(global.add);
    router.roomEvents.listen(room.add);
    router.eventsForRoom('battle-one').listen(first.add);
    await receive('>battle-one\n|init|battle\n|title|One\n|turn|1');
    await receive('>battle-two\n|init|battle\n|title|Two');
    await receive('|challstr|4|challenge\n|updateuser|Alice|1|1\n\n');
    expect(first.map((value) => value.event.runtimeType), [
      RoomInitEvent,
      RoomTitleEvent,
      BattleTurnEvent,
    ]);
    expect(room.map((value) => value.roomId), [
      'battle-one',
      'battle-one',
      'battle-one',
      'battle-two',
      'battle-two',
    ]);
    expect(global.map((event) => event.runtimeType), [
      ChallengeEvent,
      UpdateUserEvent,
    ]);
    expect(router.rooms['battle-one']!.title, 'One');
    expect(router.rooms['battle-two']!.title, 'Two');
  });

  test(
    'publishes immutable snapshots before corresponding room events',
    () async {
      final snapshots = <Map<String, RoomInfo>>[];
      router.roomChanges.listen(snapshots.add);
      await receive('>room\n|init|chat');
      final old = router.rooms;
      var titleSeen = false;
      router.roomEvents.listen((value) {
        if (value.event is RoomTitleEvent) {
          titleSeen = router.rooms['room']!.title == 'Title';
        }
      });
      await receive('>room\n|title|Title');
      expect(titleSeen, isTrue);
      expect(old['room']!.title, isNull);
      expect(() => router.rooms.clear(), throwsUnsupportedError);
      expect(() => snapshots.first.clear(), throwsUnsupportedError);
      expect(snapshots, hasLength(2));
    },
  );

  test(
    'unknown rooms and malformed events do not populate the registry',
    () async {
      final room = <RoomEvent>[];
      final global = <ServerEvent>[];
      router.roomEvents.listen(room.add);
      router.globalEvents.listen(global.add);
      await receive('>unknown\n|title|Early\n|future|data\n|init|\n|deinit');
      await receive('>\n|popup|message\nplain text');
      expect(router.rooms, isEmpty);
      expect(room.map((value) => value.event.runtimeType), [
        RoomTitleEvent,
        UnknownServerEvent,
        MalformedServerEvent,
        RoomDeinitEvent,
      ]);
      expect(global.map((event) => event.runtimeType), [
        MalformedServerEvent,
        PopupEvent,
        PlainTextEvent,
      ]);
    },
  );

  test(
    'headerless lifecycle is lobby; subsequent globals remain global',
    () async {
      final room = <RoomEvent>[];
      final global = <ServerEvent>[];
      router.eventsForRoom('lobby').listen(room.add);
      router.globalEvents.listen(global.add);
      await receive('|init|chat\n|title|Lobby');
      expect(router.rooms['lobby']!.title, 'Lobby');
      expect(room.every((value) => value.roomId == 'lobby'), isTrue);
      expect(room.first.event.roomId, isNull);
      await receive('|challstr|4|secret');
      expect(global.single, isA<ChallengeEvent>());
      await receive('|deinit');
      expect(router.rooms, isEmpty);
    },
  );

  test(
    'reinitialization resets title and deinit removes only its room',
    () async {
      await receive('>one\n|init|chat\n|title|Old\n>two\n|init|battle');
      await receive('>one\n|init|future-room-type');
      expect(router.rooms['one']!.type, 'future-room-type');
      expect(router.rooms['one']!.title, isNull);
      await receive('>one\n|deinit\n|title|Ignored');
      expect(router.rooms.keys, ['two']);
    },
  );

  test(
    'disconnect preserves stale metadata until a new init for each room',
    () async {
      await receive('>one\n|init|chat\n|title|Old\n>two\n|init|battle');
      await transport.disconnect();
      await flush();
      expect(router.rooms.values.every((room) => room.isStale), isTrue);
      expect(router.rooms['one']!.title, 'Old');
      final old = socket;
      socket = FakeSocketChannel();
      final connecting = transport.connect(Uri.parse('wss://example.test'));
      socket.handshake.complete();
      await connecting;
      await receive('>one\n|title|Still stale');
      expect(router.rooms['one']!.isStale, isTrue);
      await receive('>one\n|init|chat\n|title|New');
      expect(router.rooms['one']!.isStale, isFalse);
      expect(router.rooms['two']!.isStale, isTrue);
      await old.incoming.close();
    },
  );

  test(
    'queued data followed immediately by close cannot become fresh again',
    () async {
      socket.incoming.add('>one\n|init|chat\n|title|Last');
      socket.incoming.add('>two\n|init|battle');
      await socket.incoming.close();
      await flush();
      expect(router.rooms.keys, ['one', 'two']);
      expect(router.rooms.values.every((room) => room.isStale), isTrue);
    },
  );

  test('transport dispose marks rooms stale', () async {
    await receive('>one\n|init|chat');
    await transport.dispose();
    await flush();
    expect(router.rooms['one']!.isStale, isTrue);
  });

  test(
    'router disposal closes streams and does not dispose the transport',
    () async {
      await receive('>one\n|init|chat');
      final done = Future.wait([
        router.globalEvents.drain<void>(),
        router.roomEvents.drain<void>(),
        router.roomChanges.drain<void>(),
      ]);
      await router.dispose();
      await done;
      await router.dispose();
      expect(transport.status, TransportStatus.connected);
      expect(router.rooms['one']!.isStale, isTrue);
      await receive('>two\n|init|battle');
      expect(router.rooms.keys, ['one']);
    },
  );
}
