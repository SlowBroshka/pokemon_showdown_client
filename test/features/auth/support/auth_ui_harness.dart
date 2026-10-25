import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pokemon_showdown_client/core/auth/auth_api_client.dart';
import 'package:pokemon_showdown_client/core/auth/auth_controller.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';

import '../../../core/auth/support/fake_auth_http_client.dart';
import '../../../core/transport/support/fake_socket_channel.dart';

final class AuthUiHarness {
  AuthUiHarness() {
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    auth = AuthController(
      session: session,
      api: AuthApiClient(
        clientFactory: () {
          final client = FakeAuthHttpClient((request) => respond(request));
          clients.add(client);
          return client;
        },
      ),
    );
    connection = ConnectionController(session: session);
  }

  final socket = FakeSocketChannel();
  final clients = <FakeAuthHttpClient>[];
  late final ShowdownSession session;
  late final AuthController auth;
  late final ConnectionController connection;
  FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond = (_) =>
      success();

  static http.StreamedResponse success() => http.StreamedResponse(
    Stream.value(
      utf8.encode(
        ']${jsonEncode({
          'curuser': {'loggedin': true, 'username': 'ExampleUser'},
          'assertion': 'synthetic,exampleuser,2,0,example.invalid;not-a-signature',
        })}',
      ),
    ),
    200,
  );

  Future<void> dispose() async {
    connection.dispose();
    await auth.dispose();
    await connection.closed;
    await session.dispose();
    await socket.incoming.close();
  }
}
