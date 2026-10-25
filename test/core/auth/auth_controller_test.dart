import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pokemon_showdown_client/core/auth/auth_api_client.dart';
import 'package:pokemon_showdown_client/core/auth/auth_controller.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../transport/support/fake_socket_channel.dart';
import 'support/fake_auth_http_client.dart';

const _endpoint = 'wss://sim3.psim.us/showdown/websocket';
const _assertion = 'synthetic,exampleuser,2,0,example.invalid;not-a-signature';
http.StreamedResponse success() => http.StreamedResponse(
  Stream.value(
    utf8.encode(
      ']${jsonEncode({
        'curuser': {'loggedin': true, 'username': 'ExampleUser'},
        'assertion': _assertion,
      })}',
    ),
  ),
  200,
);

Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ShowdownSession session;
  late AuthController controller;
  late FakeSocketChannel socket;
  late List<FakeSocketChannel> sockets;
  late List<FakeAuthHttpClient> clients;
  late FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;

  AuthController create({
    Duration challengeTimeout = const Duration(seconds: 10),
    Duration confirmationTimeout = const Duration(seconds: 10),
  }) => AuthController(
    session: session,
    api: AuthApiClient(
      clientFactory: () {
        final client = FakeAuthHttpClient((request) => respond(request));
        clients.add(client);
        return client;
      },
    ),
    challengeTimeout: challengeTimeout,
    confirmationTimeout: confirmationTimeout,
  );

  setUp(() {
    socket = FakeSocketChannel();
    sockets = [socket];
    clients = [];
    respond = (_) => success();
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    controller = create();
  });
  tearDown(() async {
    await controller.dispose();
    await session.dispose();
    for (final value in sockets) {
      await value.incoming.close();
    }
  });

  Future<void> receive(String text) async {
    socket.incoming.add(text);
    await settle();
  }

  Future<void> connect({
    String endpoint = _endpoint,
    bool challenge = true,
  }) async {
    final pending = session.connect(Uri.parse(endpoint));
    socket.handshake.complete();
    await pending;
    await settle();
    if (challenge) await receive('|challstr|0|synthetic-challenge');
  }

  Future<void> start() =>
      controller.login(username: 'ExampleUser', password: 'private-password');

  test(
    'unavailable login is a no-op and no network starts at construction',
    () async {
      expect(controller.state.phase, AuthPhase.disconnected);
      expect(controller.canLogin, isFalse);
      await start();
      expect(clients, isEmpty);
    },
  );

  test(
    'HTTP and named alone do not authenticate; matching fresh updateuser does',
    () async {
      await connect();
      await receive('|updateuser| ExampleUser|1|1|{}');
      expect(controller.state.phase, AuthPhase.ready);
      final pending = start();
      await settle();
      expect(controller.state.phase, AuthPhase.awaitingConfirmation);
      expect(controller.state.username, isNull);
      expect(socket.sink.sent, ['|/trn ExampleUser,0,$_assertion']);
      await receive(
        '|updateuser| OtherUser|1|1|{}\n|updateuser| ExampleUser|0|1|{}',
      );
      expect(controller.state.phase, AuthPhase.awaitingConfirmation);
      await receive('|updateuser|+ExampleUser@!|1|1|{}');
      await pending;
      expect(controller.state.phase, AuthPhase.authenticated);
      expect(controller.state.username, 'ExampleUser');
      expect(controller.state.userId, 'exampleuser');
      expect(controller.canLogin, isFalse);
    },
  );

  test(
    'accepts unprefixed legacy USER and ignores room-local confirmation',
    () async {
      await connect();
      final pending = start();
      await settle();
      await receive('>one\n|updateuser| ExampleUser|1|1|{}');
      expect(controller.state.phase, AuthPhase.awaitingConfirmation);
      await receive('|updateuser|ExampleUser|1|1|{}');
      await pending;
      expect(controller.state.phase, AuthPhase.authenticated);
    },
  );

  test(
    'HTTP rejection is typed, sends no trn and permits an explicit retry',
    () async {
      respond = (_) => http.StreamedResponse(
        Stream.value(utf8.encode(']{"error":"private-server-error"}')),
        200,
      );
      await connect();
      await start();
      await settle();
      expect(controller.state.error, AuthFailure.loginRejected);
      expect(controller.canLogin, isTrue);
      expect(socket.sink.sent, isEmpty);
      respond = (_) => success();
      final pending = start();
      await settle();
      await receive('|updateuser| ExampleUser|1|1|{}');
      await pending;
      expect(controller.state.error, isNull);
      expect(clients, hasLength(2));
    },
  );

  test('duplicate login calls never duplicate HTTP or trn', () async {
    final delayed = Completer<http.StreamedResponse>();
    respond = (_) => delayed.future;
    await connect();
    final pending = start();
    await start();
    expect(clients, hasLength(1));
    delayed.complete(success());
    await settle();
    await start();
    expect(socket.sink.sent, hasLength(1));
    await receive('|updateuser| ExampleUser|1|1|{}');
    await pending;
  });

  test('cancel before trn leaves the shared connection open and ignores a late response', () async {
    final delayed = Completer<http.StreamedResponse>();
    respond = (_) => delayed.future;
    await connect();
    final pending = start();
    await controller.cancel();
    await pending;
    delayed.complete(success());
    await settle();
    expect(session.status, TransportStatus.connected);
    expect(controller.canLogin, isTrue);
    expect(controller.state.error, AuthFailure.cancelled);
    expect(socket.sink.sent, isEmpty);
    expect(clients.single.closed, isTrue);
  });

  test('new challenge before trn cancels HTTP; next explicit login uses new challenge', () async {
    final delayed = Completer<http.StreamedResponse>();
    respond = (_) => delayed.future;
    await connect();
    final old = start();
    await receive('|challstr|0|new-synthetic-challenge');
    await old;
    delayed.complete(success());
    await settle();
    expect(socket.sink.sent, isEmpty);
    expect(controller.canLogin, isTrue);
    respond = (request) {
      expect(
        (request as http.Request).bodyFields['challstr'],
        '0|new-synthetic-challenge',
      );
      return success();
    };
    final pending = start();
    await settle();
    await receive('|updateuser| ExampleUser|1|1|{}');
    await pending;
  });

  test(
    'queued challenge replacement beats an already completed HTTP reply',
    () async {
      final delayed = Completer<http.StreamedResponse>();
      respond = (_) => delayed.future;
      await connect();
      final pending = start();
      delayed.complete(success());
      socket.incoming.add('|challstr|0|new-synthetic-challenge');
      await settle();
      await pending;
      expect(socket.sink.sent, isEmpty);
      expect(controller.canLogin, isTrue);
    },
  );

  test(
    'a received pre-trn user update is not reused as confirmation',
    () async {
      final delayed = Completer<http.StreamedResponse>();
      respond = (_) => delayed.future;
      await connect();
      final pending = start();
      socket.incoming.add('|updateuser| ExampleUser|1|1|{}');
      delayed.complete(success());
      await settle();
      expect(controller.state.phase, AuthPhase.awaitingConfirmation);
      await receive('|updateuser| ExampleUser|1|1|{}');
      await pending;
      expect(controller.state.phase, AuthPhase.authenticated);
    },
  );

  test('disconnect during HTTP clears challenge; old result cannot reach a new socket', () async {
    final delayed = Completer<http.StreamedResponse>();
    respond = (_) => delayed.future;
    await connect();
    final pending = start();
    await session.disconnect();
    await settle();
    await pending;
    expect(controller.state.error, AuthFailure.connectionLost);
    socket = FakeSocketChannel();
    sockets.add(socket);
    await connect();
    delayed.complete(success());
    await settle();
    expect(socket.sink.sent, isEmpty);
    expect(controller.canLogin, isTrue);
  });

  test('cancel after trn disconnects and ignores late confirmation', () async {
    await connect();
    final pending = start();
    await settle();
    await controller.cancel();
    await pending;
    await receive('|updateuser| ExampleUser|1|1|{}');
    expect(session.status, TransportStatus.disconnected);
    expect(controller.state.phase, AuthPhase.disconnected);
    expect(controller.state.error, AuthFailure.cancelled);
    expect(controller.state.username, isNull);
  });

  test(
    'a challenge after trn disconnects instead of reusing an assertion',
    () async {
      await connect();
      final pending = start();
      await settle();
      await receive('|challstr|0|replacement');
      await pending;
      expect(session.status, TransportStatus.disconnected);
      expect(socket.sink.sent, hasLength(1));
    },
  );

  test('missing challenge times out and closes the connection', () async {
    await controller.dispose();
    controller = create(challengeTimeout: const Duration(milliseconds: 25));
    await connect(challenge: false);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(session.status, TransportStatus.disconnected);
    expect(controller.state.error, AuthFailure.challengeTimeout);
  });

  test('unrelated user updates do not reset confirmation timeout', () async {
    await controller.dispose();
    controller = create(confirmationTimeout: const Duration(milliseconds: 35));
    await connect();
    final pending = start();
    await settle();
    await receive('|updateuser| OtherUser|1|1|{}');
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await pending;
    expect(session.status, TransportStatus.disconnected);
    expect(controller.state.error, AuthFailure.confirmationTimeout);
  });

  for (final refusal in [
    '|nametaken|ExampleUser|private-server-error',
    '|nametaken||private-server-error',
    '|error|private-server-error',
    '|popup|<script>private-server-error</script>',
  ]) {
    test('global rejection after trn: $refusal', () async {
      await connect();
      final states = <AuthState>[];
      final subscription = controller.changes.listen(states.add);
      final pending = start();
      await settle();
      await receive(refusal);
      await pending;
      expect(controller.state.error, AuthFailure.identityRejected);
      expect(session.status, TransportStatus.disconnected);
      expect(states.join(), isNot(contains('private')));
      expect(states.join(), isNot(contains(_assertion)));
      await subscription.cancel();
    });
  }

  test(
    'rejection for another name and room popup do not reject this attempt',
    () async {
      await connect();
      final pending = start();
      await settle();
      await receive('|nametaken|OtherUser|private\n>one\n|popup|private');
      expect(controller.state.phase, AuthPhase.awaitingConfirmation);
      await receive('|updateuser| ExampleUser|1|1|{}');
      await pending;
    },
  );

  for (final endpoint in [
    'wss://example.test/showdown/websocket',
    'wss://sim3.psim.us:444/showdown/websocket',
    'wss://sim3.psim.us/showdown/websocket?server=other',
  ]) {
    test(
      'unsupported server cannot trigger password HTTP: $endpoint',
      () async {
        await connect(endpoint: endpoint);
        await start();
        expect(controller.state.phase, AuthPhase.unavailable);
        expect(controller.state.error, AuthFailure.unsupportedServer);
        expect(clients, isEmpty);
        expect(session.status, TransportStatus.connected);
      },
    );
  }

  test(
    'early challenge is retained, but login waits for connected status',
    () async {
      final connecting = session.connect(Uri.parse(_endpoint));
      await receive('|challstr|0|early-synthetic');
      expect(controller.canLogin, isFalse);
      await start();
      expect(clients, isEmpty);
      socket.handshake.complete();
      await connecting;
      await settle();
      expect(controller.canLogin, isTrue);
    },
  );

  for (final update in [
    '|updateuser| Guest 123|0|1|{}',
    '|updateuser| OtherUser|1|1|{}',
  ]) {
    test(
      'confirmed identity is revoked on server identity change: $update',
      () async {
        await connect();
        final pending = start();
        await settle();
        await receive('|updateuser| ExampleUser|1|1|{}');
        await pending;
        await receive(update);
        expect(controller.state.username, isNull);
        expect(controller.state.error, AuthFailure.identityRejected);
        expect(session.status, TransportStatus.disconnected);
      },
    );
  }

  test('dispose before trn cancels HTTP without disposing or disconnecting shared session', () async {
    final delayed = Completer<http.StreamedResponse>();
    respond = (_) => delayed.future;
    await connect();
    final pending = start();
    final disposal = controller.dispose();
    expect(identical(disposal, controller.dispose()), isTrue);
    await disposal;
    await pending;
    delayed.completeError(StateError('private-late-error'));
    await settle();
    expect(controller.state.phase, AuthPhase.disposed);
    expect(session.status, TransportStatus.connected);
    expect(clients.single.closed, isTrue);
    expect(socket.sink.sent, isEmpty);
  });

  test(
    'dispose after trn disconnects the session without disposing its owner',
    () async {
      await connect();
      final pending = start();
      await settle();
      await controller.dispose();
      await pending;
      expect(session.status, TransportStatus.disconnected);
      expect(controller.state.phase, AuthPhase.disposed);
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect();
      expect(session.status, TransportStatus.connected);
      expect(controller.canLogin, isFalse);
    },
  );

  test(
    'session owner disposal invalidates HTTP work via stream completion',
    () async {
      final delayed = Completer<http.StreamedResponse>();
      respond = (_) => delayed.future;
      await connect();
      final pending = start();
      await session.dispose();
      await pending;
      expect(controller.state.phase, AuthPhase.disconnected);
      expect(controller.state.error, AuthFailure.connectionLost);
      delayed.complete(success());
      await settle();
      expect(socket.sink.sent, isEmpty);
    },
  );

  test(
    'malformed challenge and malformed identity confirmation terminate safely',
    () async {
      await connect(challenge: false);
      await receive('|challstr|');
      expect(controller.state.error, AuthFailure.invalidServerEvent);
      expect(session.status, TransportStatus.disconnected);
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect();
      final pending = start();
      await settle();
      await receive('|updateuser|ExampleUser|2|1');
      await pending;
      expect(controller.state.error, AuthFailure.invalidServerEvent);
    },
  );

  test('input errors are safe and do not send HTTP or trn', () async {
    await connect();
    await controller.login(
      username: 'private|name',
      password: 'private-password',
    );
    await settle();
    expect(controller.state.error, AuthFailure.invalidInput);
    expect(controller.canLogin, isTrue);
    expect(clients, isEmpty);
    expect(socket.sink.sent, isEmpty);
  });

  test('send failure invalidates the attempt and disconnects', () async {
    await connect();
    socket.sink.failSend = true;
    await start();
    await settle();
    expect(controller.state.error, AuthFailure.sendFailed);
    expect(controller.state.username, isNull);
    expect(session.status, TransportStatus.disconnected);
  });

  test('accepts the explicit standard WSS port', () async {
    await connect(endpoint: 'wss://sim3.psim.us:443/showdown/websocket');
    expect(controller.canLogin, isTrue);
  });

  test(
    'challenge timeout does not replace the transport handshake timeout',
    () async {
      await controller.dispose();
      controller = create(challengeTimeout: const Duration(milliseconds: 25));
      final pending = session.connect(Uri.parse(_endpoint));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(session.status, TransportStatus.connecting);
      socket.handshake.complete();
      await pending;
      await receive('|challstr|0|synthetic-challenge');
      expect(controller.canLogin, isTrue);
    },
  );

  test('invalid challenge payload is rejected before enabling login', () async {
    await connect(challenge: false);
    await receive('|challstr|not-a-full-challenge');
    expect(controller.state.error, AuthFailure.invalidServerEvent);
    expect(session.status, TransportStatus.disconnected);
    expect(controller.canLogin, isFalse);
    expect(clients, isEmpty);
  });
}
