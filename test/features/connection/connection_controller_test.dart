import 'package:pokemon_showdown_client/features/connection/connection_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../../core/transport/support/fake_socket_channel.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSocketChannel socket;
  late ShowdownTransport transport;
  late ConnectionController controller;
  setUp(() {
    socket = FakeSocketChannel();
    transport = ShowdownTransport(channelFactory: (_) => socket);
    controller = ConnectionController(
      transport: transport,
      roomTimeout: const Duration(seconds: 10),
    );
  });
  tearDown(() async {
    controller.dispose();
    await controller.closed;
    await socket.incoming.close();
  });
  Future<void> connect() async {
    final pending = controller.connect('wss://example.test');
    socket.handshake.complete();
    await pending;
    await flush();
  }

  Future<void> receive(String message) async {
    socket.incoming.add(message);
    await flush();
  }

  test('validates address and room before sending', () async {
    await controller.connect('https://example.test');
    expect(controller.error, isNotNull);
    expect(controller.status, TransportStatus.disconnected);
    await connect();
    controller.join('bad|id');
    expect(socket.sink.sent, isEmpty);
    expect(controller.canJoin, isTrue);
  });
  test('cancellation and failed handshake leave the screen usable', () async {
    final pending = controller.connect('wss://example.test');
    expect(controller.canConnect, isFalse);
    await controller.disconnect();
    await pending;
    expect(controller.canConnect, isTrue);
    socket.handshake.completeError(StateError('private-secret'));
    await flush();
    expect(controller.error, isNull);
    expect(controller.notices.join(), isNot(contains('private-secret')));
  });
  test('handshake failure is reported without raw details', () async {
    final pending = controller.connect('wss://example.test');
    socket.handshake.completeError(StateError('private-secret'));
    await pending;
    await flush();
    expect(controller.error, ConnectionMessage.connectionFailed);
    expect(controller.notices.join(), isNot(contains('private-secret')));
  });
  test(
    'one room only, waiting for init and deinit and preserving title',
    () async {
      await connect();
      controller.join('one');
      controller.join('two');
      expect(socket.sink.sent, ['|/join one']);
      expect(controller.room, isNull);
      expect(controller.canJoin, isFalse);
      await receive('>one\n|init|chat\n|title|First room');
      expect(controller.room!.title, 'First room');
      expect(controller.canJoin, isFalse);
      controller.leave();
      controller.leave();
      expect(socket.sink.sent, ['|/join one', 'one|/leave']);
      expect(controller.room, isNotNull);
      expect(controller.leaving, isTrue);
      await receive('>one\n|deinit');
      expect(controller.room, isNull);
      expect(controller.canJoin, isTrue);
    },
  );
  test('unsolicited rooms are left, not made active', () async {
    await connect();
    controller.join('one');
    await receive('>two\n|init|chat');
    expect(controller.joiningId, 'one');
    expect(controller.room, isNull);
    expect(socket.sink.sent, ['|/join one', 'two|/leave']);
    await receive('>one\n|init|chat');
    expect(controller.room!.id, 'one');
  });
  test(
    'a rejected join disconnects and never displays raw server content',
    () async {
      await connect();
      controller.join('one');
      await receive('>one\n|noinit|joinfailed|<script>secret</script>');
      expect(controller.status, TransportStatus.disconnected);
      expect(controller.notices.join(), isNot(contains('secret')));
      expect(controller.joiningId, isNull);
    },
  );
  test(
    'timed-out operation disconnects instead of allowing an ambiguous retry',
    () async {
      controller.dispose();
      await controller.closed;
      transport = ShowdownTransport(channelFactory: (_) => socket);
      controller = ConnectionController(
        transport: transport,
        roomTimeout: const Duration(milliseconds: 20),
      );
      await connect();
      controller.join('one');
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(controller.status, TransportStatus.disconnected);
      expect(controller.error, ConnectionMessage.roomTimeout);
      expect(controller.canJoin, isFalse);
      expect(controller.joiningId, isNull);
    },
  );
  test(
    'repeated init while leaving does not cancel the pending leave',
    () async {
      await connect();
      controller.join('one');
      await receive('>one\n|init|chat');
      controller.leave();
      await receive('>one\n|init|chat');
      expect(controller.leaving, isTrue);
      expect(controller.canJoin, isFalse);
      await receive('>one\n|deinit');
      expect(controller.canJoin, isTrue);
    },
  );
  test(
    'disconnect keeps stale room, reconnect clears it without autojoin',
    () async {
      await connect();
      controller.join('one');
      await receive('>one\n|init|chat\n|title|Old');
      await controller.disconnect();
      await flush();
      expect(controller.room!.isStale, isTrue);
      expect(controller.canLeave, isFalse);
      final old = socket;
      socket = FakeSocketChannel();
      await connect();
      expect(controller.room, isNull);
      expect(socket.sink.sent, isEmpty);
      await old.incoming.close();
    },
  );
  test(
    'history is bounded and ignores sensitive and unsupported messages',
    () async {
      await connect();
      await receive(
        '|challstr|4|secret\n|updateuser|SecretUser|1|1\n|html|secret',
      );
      for (var index = 0; index < 55; index++) {
        await receive('|popup|secret');
      }
      expect(controller.notices, hasLength(50));
      expect(controller.notices.join(), isNot(contains('secret')));
      expect(controller.notices.join(), isNot(contains('SecretUser')));
      expect(() => controller.notices.clear(), throwsUnsupportedError);
    },
  );
  test(
    'dispose during connecting cancels work and closes owned resources',
    () async {
      final pending = controller.connect('wss://example.test');
      controller.dispose();
      await controller.closed;
      await pending;
      expect(transport.status, TransportStatus.disposed);
      socket.handshake.complete();
      await flush();
      expect(controller.canJoin, isFalse);
    },
  );
}
