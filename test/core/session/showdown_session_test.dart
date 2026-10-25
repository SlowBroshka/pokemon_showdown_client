import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/client_commands.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../transport/support/fake_socket_channel.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late List<FakeSocketChannel> sockets;
  late FakeSocketChannel socket;
  late ShowdownTransport transport;
  late ShowdownSession session;

  setUp(() {
    sockets = [];
    socket = FakeSocketChannel();
    sockets.add(socket);
    transport = ShowdownTransport(channelFactory: (_) => socket);
    session = ShowdownSession(transport: transport);
  });

  tearDown(() async {
    await session.dispose();
    for (final value in sockets) {
      await value.incoming.close();
    }
  });

  Future<void> connect() async {
    final pending = session.connect(Uri.parse('wss://example.test'));
    socket.handshake.complete();
    await pending;
    await flush();
  }

  void nextSocket() {
    socket = FakeSocketChannel();
    sockets.add(socket);
  }

  test('does not connect until requested; invalid URI consumes no epoch', () {
    expect(session.status, TransportStatus.disconnected);
    expect(session.connectionEpoch, 0);
    expect(session.isCurrent(0), isFalse);
    expect(
      () => session.connect(Uri.parse('http://example.test')),
      throwsArgumentError,
    );
    expect(session.connectionEpoch, 0);
    expect(socket.sink.sent, isEmpty);
  });

  test(
    'source sequence is preserved across routing before subscriber delivery',
    () async {
      final updates = <SessionUpdate>[];
      final subscription = session.updates.listen(updates.add)..pause();
      await connect();
      final before = session.latestUpdateSequence;
      socket.incoming.add('|challstr|0|synthetic\n|updateuser| Guest 1|0|1|{}');
      await flush();
      final received = session.latestUpdateSequence;
      expect(received, greaterThan(before));
      expect(updates, isEmpty);
      subscription.resume();
      await flush();
      final events = updates.where((u) => u.event != null).toList();
      expect(events, hasLength(2));
      expect(events.map((u) => u.sequence), [received, received]);
      expect(session.endpoint, Uri.parse('wss://example.test'));
      await subscription.cancel();
    },
  );

  test('routes once with epoch and preserves lifecycle/event order', () async {
    final updates = <SessionUpdate>[];
    final globals = <SessionUpdate>[];
    final room = <SessionUpdate>[];
    final subscriptions = [
      session.updates.listen(updates.add),
      session.globalEvents.listen(globals.add),
      session.eventsForRoom('one').listen(room.add),
    ];
    await connect();
    socket.incoming.add('|challstr|0|synthetic\n>one\n|init|chat\n|title|One');
    await flush();
    await session.disconnect();
    await flush();
    expect(updates.map((u) => u.status ?? u.event.runtimeType), [
      TransportStatus.connecting,
      TransportStatus.connected,
      ChallengeEvent,
      RoomInitEvent,
      RoomTitleEvent,
      TransportStatus.disconnected,
    ]);
    expect(updates.every((u) => u.connectionEpoch == 1), isTrue);
    expect(globals.single.event, isA<ChallengeEvent>());
    expect(room.map((u) => u.roomId), ['one', 'one']);
    expect(session.rooms['one']!.isStale, isTrue);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });

  test('reconnect rejects an old async result before sending', () async {
    await connect();
    final capturedEpoch = session.connectionEpoch;
    await session.disconnect();
    expect(session.isCurrent(capturedEpoch), isFalse);
    nextSocket();
    await connect();
    expect(session.connectionEpoch, 2);
    expect(
      () => session.send(
        TrnCommand(username: 'ExampleUser', assertion: 'synthetic;invalid'),
        connectionEpoch: capturedEpoch,
      ),
      throwsStateError,
    );
    expect(socket.sink.sent, isEmpty);
    session.send(JoinRoomCommand(roomId: 'one'), connectionEpoch: 2);
    expect(socket.sink.sent, ['|/join one']);
  });

  test('obsolete queued events keep their original epoch', () async {
    final updates = <SessionUpdate>[];
    final subscription = session.updates.listen(updates.add);
    subscription.pause();
    await connect();
    socket.incoming.add('|challstr|0|old-synthetic');
    await flush();
    await session.disconnect();
    nextSocket();
    // Start the next attempt without draining the preceding status notifications.
    final pending = session.connect(Uri.parse('wss://example.test'));
    expect(session.connectionEpoch, 2);
    socket.handshake.complete();
    await pending;
    socket.incoming.add('|challstr|0|new-synthetic');
    await flush();
    expect(updates, isEmpty);
    subscription.resume();
    await flush();
    final challenges = updates.where((u) => u.event is ChallengeEvent).toList();
    expect(challenges.map((u) => u.connectionEpoch), [1, 2]);
    expect(session.isCurrent(challenges.first.connectionEpoch), isFalse);
    expect(session.isCurrent(challenges.last.connectionEpoch), isTrue);
    await subscription.cancel();
  });

  test('convenience streams drop events invalidated before delivery', () async {
    await connect();
    // This listener runs before the convenience subscriber receives the event.
    final invalidator = session.updates.listen((update) {
      if (update.event is ChallengeEvent) unawaited(session.disconnect());
    });
    final globals = <SessionUpdate>[];
    final subscriber = session.globalEvents.listen(globals.add);
    socket.incoming.add('|challstr|0|synthetic');
    await flush();
    expect(globals, isEmpty);
    expect(session.status, TransportStatus.disconnected);
    await invalidator.cancel();
    await subscriber.cancel();
  });

  test(
    'failed and cancelled handshakes consume epochs, old socket is ignored',
    () async {
      final first = session.connect(Uri.parse('wss://example.test'));
      final firstFailure = expectLater(
        first,
        throwsA(isA<TransportException>()),
      );
      socket.handshake.completeError(StateError('private'));
      await firstFailure;
      expect(session.connectionEpoch, 1);
      nextSocket();
      final cancelledSocket = socket;
      final second = session.connect(Uri.parse('wss://example.test'));
      final secondFailure = expectLater(
        second,
        throwsA(isA<TransportException>()),
      );
      await session.disconnect();
      await secondFailure;
      nextSocket();
      await connect();
      final globals = <SessionUpdate>[];
      final subscription = session.globalEvents.listen(globals.add);
      cancelledSocket.handshake.complete();
      cancelledSocket.incoming.add('|challstr|0|old-synthetic');
      await flush();
      expect(session.connectionEpoch, 3);
      expect(session.status, TransportStatus.connected);
      expect(globals, isEmpty);
      await subscription.cancel();
    },
  );

  test(
    'captures an early challenge during handshake without enabling send',
    () async {
      final globals = <SessionUpdate>[];
      final subscription = session.globalEvents.listen(globals.add);
      final pending = session.connect(Uri.parse('wss://example.test'));
      socket.incoming.add('|challstr|0|early-synthetic');
      await flush();
      expect(globals.single.connectionEpoch, 1);
      expect(session.isCurrent(1), isTrue);
      expect(
        () => session.send(JoinRoomCommand(roomId: 'one'), connectionEpoch: 1),
        throwsStateError,
      );
      socket.handshake.complete();
      await pending;
      await subscription.cancel();
    },
  );

  test(
    'dispose cancels handshake, closes streams and is terminal/idempotent',
    () async {
      final done = Completer<void>();
      session.updates.listen((_) {}, onDone: done.complete);
      final pending = session.connect(Uri.parse('wss://example.test'));
      final failed = expectLater(pending, throwsA(isA<TransportException>()));
      final disposal = session.dispose();
      expect(session.isCurrent(1), isFalse);
      expect(identical(disposal, session.dispose()), isTrue);
      await disposal;
      await failed;
      await done.future;
      expect(transport.status, TransportStatus.disposed);
      expect(socket.sink.closed, isTrue);
      expect(
        () => session.connect(Uri.parse('wss://example.test')),
        throwsStateError,
      );
      socket.handshake.complete();
      await flush();
    },
  );

  test(
    'two consumers share a socket; cancelling one does not disconnect',
    () async {
      final first = <SessionUpdate>[];
      final second = <SessionUpdate>[];
      final a = session.globalEvents.listen(first.add);
      final b = session.globalEvents.listen(second.add);
      await connect();
      socket.incoming.add('|challstr|0|first-synthetic');
      await flush();
      await a.cancel();
      socket.incoming.add('|challstr|0|second-synthetic');
      await flush();
      expect(first, hasLength(1));
      expect(second, hasLength(2));
      expect(session.status, TransportStatus.connected);
      await b.cancel();
    },
  );
}
