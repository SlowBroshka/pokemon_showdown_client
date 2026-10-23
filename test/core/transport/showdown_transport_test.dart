import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:pokemon_showdown_client/core/protocol/client_commands.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import 'support/fake_socket_channel.dart';

final endpoint = Uri.parse('wss://example.test/showdown/websocket');
Future<void> flush() => Future<void>.delayed(Duration.zero);
Matcher failure(TransportFailure value) => isA<TransportException>().having(
  (error) => error.failure,
  'failure',
  value,
);

void main() {
  late FakeSocketChannel socket;
  late ShowdownTransport transport;

  setUp(() {
    socket = FakeSocketChannel();
    transport = ShowdownTransport(channelFactory: (_) => socket);
  });
  tearDown(() async {
    await transport.dispose();
    await socket.incoming.close();
  });

  Future<void> connect() async {
    final result = transport.connect(endpoint);
    socket.handshake.complete();
    await result;
  }

  test(
    'waits for handshake and preserves complete messages and their order',
    () async {
      final states = <TransportStatus>[];
      final messages = <String>[];
      transport.statuses.listen(states.add);
      transport.messages.listen(messages.add);
      expect(transport.status, TransportStatus.disconnected);
      final result = transport.connect(endpoint);
      expect(transport.status, TransportStatus.connecting);
      expect(
        () => transport.send(JoinRoomCommand(roomId: 'lobby')),
        throwsStateError,
      );
      socket.handshake.complete();
      await result;
      socket.incoming.add('>battle-one\n|init|battle\n|turn|1');
      socket.incoming.add('|challstr|4|data');
      await flush();
      expect(messages, [
        '>battle-one\n|init|battle\n|turn|1',
        '|challstr|4|data',
      ]);
      expect(states, [TransportStatus.connecting, TransportStatus.connected]);
      transport.send(JoinRoomCommand(roomId: 'lobby'));
      expect(socket.sink.sent, ['|/join lobby']);
    },
  );

  test('rejects overlapping connects and sends while disconnected', () async {
    expect(
      () => transport.send(LeaveRoomCommand(roomId: 'lobby')),
      throwsStateError,
    );
    await connect();
    expect(() => transport.connect(endpoint), throwsStateError);
    await transport.disconnect();
    expect(socket.sink.closed, isTrue);
    expect(
      () => transport.send(JoinRoomCommand(roomId: 'lobby')),
      throwsStateError,
    );
    expect(socket.sink.sent, isEmpty);
    await transport.disconnect();
  });

  test(
    'cancels connecting and ignores late handshake after reconnect',
    () async {
      final oldSocket = socket;
      final pending = transport.connect(endpoint);
      final rejected = expectLater(
        pending,
        throwsA(failure(TransportFailure.cancelled)),
      );
      await transport.disconnect();
      await rejected;
      expect(oldSocket.sink.closed, isTrue);
      socket = FakeSocketChannel();
      await connect();
      oldSocket.handshake.complete();
      oldSocket.incoming.addError(StateError('late secret'));
      await flush();
      expect(transport.status, TransportStatus.connected);
      expect(socket.sink.sent, isEmpty);
      await oldSocket.incoming.close();
    },
  );

  test(
    'reports failed handshake once without exposing error details',
    () async {
      final errors = <TransportException>[];
      transport.failures.listen(errors.add);
      final pending = transport.connect(endpoint);
      final rejected = expectLater(
        pending,
        throwsA(failure(TransportFailure.connection)),
      );
      socket.handshake.completeError(StateError('private token'));
      socket.incoming.addError(StateError('private token'));
      await rejected;
      await flush();
      expect(errors, hasLength(1));
      expect(errors.single.toString(), isNot(contains('private token')));
      expect(transport.status, TransportStatus.disconnected);
      expect(socket.sink.closed, isTrue);
    },
  );

  test('times out handshake and closes the abandoned channel', () async {
    await transport.dispose();
    transport = ShowdownTransport(
      channelFactory: (_) => socket,
      connectTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      transport.connect(endpoint),
      throwsA(failure(TransportFailure.timeout)),
    );
    expect(transport.status, TransportStatus.disconnected);
    expect(socket.sink.closed, isTrue);
    socket.handshake.completeError(StateError('late failure'));
    await flush();
    expect(transport.status, TransportStatus.disconnected);
  });

  test('handles factory failure', () async {
    await transport.dispose();
    transport = ShowdownTransport(
      channelFactory: (_) => throw StateError('secret'),
    );
    await expectLater(
      transport.connect(endpoint),
      throwsA(failure(TransportFailure.connection)),
    );
    expect(transport.status, TransportStatus.disconnected);
  });

  test('handles remote close while connecting', () async {
    final pending = transport.connect(endpoint);
    final rejected = expectLater(
      pending,
      throwsA(failure(TransportFailure.closed)),
    );
    await socket.incoming.close();
    await rejected;
    socket.handshake.complete();
    await flush();
    expect(transport.status, TransportStatus.disconnected);
  });

  test('remote close disconnects without retrying', () async {
    final errors = <TransportException>[];
    transport.failures.listen(errors.add);
    await connect();
    await socket.incoming.close();
    await flush();
    expect(transport.status, TransportStatus.disconnected);
    expect(errors.single.failure, TransportFailure.closed);
    expect(socket.sink.sent, isEmpty);
  });

  test('stream errors disconnect an established connection', () async {
    final errors = <TransportException>[];
    transport.failures.listen(errors.add);
    await connect();
    socket.incoming.addError(StateError('socket error'));
    await flush();
    expect(transport.status, TransportStatus.disconnected);
    expect(errors.single.failure, TransportFailure.connection);
  });

  test(
    'rejects binary messages without converting them to protocol text',
    () async {
      final messages = <String>[];
      final errors = <TransportException>[];
      transport.messages.listen(messages.add);
      transport.failures.listen(errors.add);
      await connect();
      socket.incoming.add([1, 2, 3]);
      await flush();
      expect(messages, isEmpty);
      expect(errors.single.failure, TransportFailure.unsupportedMessage);
      expect(transport.status, TransportStatus.disconnected);
    },
  );

  test('send failure disconnects and never retries the command', () async {
    await connect();
    socket.sink.failSend = true;
    expect(
      () => transport.send(TrnCommand(username: 'Alice', assertion: 'token')),
      throwsA(failure(TransportFailure.send)),
    );
    expect(transport.status, TransportStatus.disconnected);
    expect(socket.sink.sent, isEmpty);
  });

  test(
    'dispose during handshake is terminal and closes event streams',
    () async {
      final states = <TransportStatus>[];
      final statusesDone = Completer<void>();
      transport.statuses.listen(states.add, onDone: statusesDone.complete);
      final messagesDone = transport.messages.drain<void>();
      final failuresDone = transport.failures.drain<void>();
      final pending = transport.connect(endpoint);
      final rejected = expectLater(
        pending,
        throwsA(failure(TransportFailure.cancelled)),
      );
      await transport.dispose();
      await rejected;
      await Future.wait([statusesDone.future, messagesDone, failuresDone]);
      socket.handshake.complete();
      await flush();
      expect(transport.status, TransportStatus.disposed);
      expect(states.last, TransportStatus.disposed);
      expect(() => transport.connect(endpoint), throwsStateError);
      await transport.disconnect();
      await transport.dispose();
    },
  );

  test('close is bounded when the peer never finishes closing', () async {
    await transport.dispose();
    transport = ShowdownTransport(
      channelFactory: (_) => socket,
      closeTimeout: const Duration(milliseconds: 10),
    );
    await connect();
    socket.sink.hangOnClose = true;
    await transport.disconnect().timeout(const Duration(seconds: 1));
    expect(transport.status, TransportStatus.disconnected);
    socket.sink.completed.complete();
  });

  test('validates endpoints and durations before opening a connection', () {
    for (final uri in [
      'ws://example.test',
      'https://example.test',
      'wss:',
      'wss://user:secret@example.test',
      'wss://example.test/#fragment',
    ]) {
      expect(() => transport.connect(Uri.parse(uri)), throwsArgumentError);
    }
    expect(transport.status, TransportStatus.disconnected);
    expect(
      () => ShowdownTransport(connectTimeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => ShowdownTransport(closeTimeout: const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });

  test(
    'exchanges text with a real local WebSocket through the channel adapter',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<WebSocket>();
      final received = Completer<String>();
      final subscription = server.listen((request) async {
        final peer = await WebSocketTransformer.upgrade(request);
        accepted.complete(peer);
        peer.listen((dynamic value) {
          received.complete(value as String);
        });
        peer.add('|challstr|4|local-test');
      });
      await transport.dispose();
      transport = ShowdownTransport(
        channelFactory: (_) =>
            IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
      );
      try {
        final message = transport.messages.first;
        await transport.connect(endpoint);
        expect(
          await message.timeout(const Duration(seconds: 2)),
          '|challstr|4|local-test',
        );
        transport.send(JoinRoomCommand(roomId: 'lobby'));
        expect(
          await received.future.timeout(const Duration(seconds: 2)),
          '|/join lobby',
        );
        final closed = transport.failures.first;
        await (await accepted.future).close();
        expect(
          (await closed.timeout(const Duration(seconds: 2))).failure,
          TransportFailure.closed,
        );
      } finally {
        await transport.dispose();
        if (accepted.isCompleted) await (await accepted.future).close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
