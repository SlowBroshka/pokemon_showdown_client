import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pokemon_showdown_client/core/auth/auth_api_client.dart';

import 'support/fake_auth_http_client.dart';

const _assertion = 'synthetic,exampleuser,2,0,example.invalid;not-a-signature';
const _password = ' private+&=пароль|secret ';
const _challenge = '0|synthetic|challenge';

String successBody({
  String username = 'ExampleUser',
  String assertion = _assertion,
}) =>
    ']${jsonEncode({
      'curuser': {'loggedin': true, 'username': username},
      'assertion': assertion,
    })}';

http.StreamedResponse response(
  String body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  status,
  headers: headers ?? {},
);

Matcher failsWith(AuthFailure failure) => throwsA(
  isA<AuthException>()
      .having((e) => e.failure, 'failure', failure)
      .having(
        (e) => e.toString(),
        'safe description',
        isNot(contains('private')),
      ),
);

Future<AuthLoginResult> login(AuthApiClient api) => api.login(
  username: 'ExampleUser',
  password: _password,
  challstr: _challenge,
);

void main() {
  final fixtures = jsonDecode(
    File('test/fixtures/auth/http-responses.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final fixture in fixtures['cases'] as List) {
    if (fixture['operation'] == 'upkeep') continue;
    test('contract fixture: ${fixture['id']}', () async {
      final client = FakeAuthHttpClient(
        (_) => response(
          fixture['body'] as String,
          status: fixture['status'] as int,
        ),
      );
      final api = AuthApiClient(clientFactory: () => client);
      addTearDown(api.dispose);
      if (fixture['expected'] == 'assertionReady') {
        final result = await login(api);
        expect(result.username, 'ExampleUser');
        expect(result.userId, 'exampleuser');
        expect(result.assertion, _assertion);
        expect(result.toString(), 'AuthLoginResult(redacted)');
        expect(result.toString(), isNot(contains(_assertion)));
      } else {
        final failure = AuthFailure.values.byName(
          fixture['expected'] as String,
        );
        await expectLater(login(api), failsWith(failure));
      }
      expect(client.requests, hasLength(1));
      expect(client.closed, isTrue);
    });
  }

  test(
    'sends exact form fields to the fixed HTTPS endpoint, without redirects',
    () async {
      final client = FakeAuthHttpClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://play.pokemonshowdown.com/~~showdown/action.php',
        );
        expect(request.url.query, isEmpty);
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(
          request.headers['content-type'],
          contains('application/x-www-form-urlencoded'),
        );
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')),
        );
        final encoded = await request.finalize().bytesToString();
        expect(Uri.splitQueryString(encoded), {
          'act': 'login',
          'name': 'ExampleUser',
          'pass': _password,
          'challstr': _challenge,
        });
        return response(successBody(), headers: {'content-type': 'text/plain'});
      });
      final api = AuthApiClient(clientFactory: () => client);
      addTearDown(api.dispose);
      await login(api);
    },
  );

  test(
    'uses a fresh client per attempt and does not copy response cookies',
    () async {
      final clients = <FakeAuthHttpClient>[];
      final api = AuthApiClient(
        clientFactory: () {
          final client = FakeAuthHttpClient((request) {
            expect(
              request.headers.keys.map((k) => k.toLowerCase()),
              isNot(contains('cookie')),
            );
            return response(
              successBody(),
              headers: {
                'set-cookie': 'sid=synthetic-private; Secure; HttpOnly',
              },
            );
          });
          clients.add(client);
          return client;
        },
      );
      addTearDown(api.dispose);
      await login(api);
      await login(api);
      expect(clients, hasLength(2));
      expect(clients.every((c) => c.closed), isTrue);
    },
  );

  test('validates input before creating any network adapter', () async {
    var calls = 0;
    final api = AuthApiClient(
      clientFactory: () {
        calls++;
        throw StateError('Must not be called');
      },
    );
    addTearDown(api.dispose);
    for (final name in [
      '',
      ' ExampleUser',
      'ExampleUser ',
      'private|name',
      'private,name',
      'private;name',
      '---',
      'Русский',
      'a' * 19,
      'private\n',
    ]) {
      await expectLater(
        api.login(username: name, password: _password, challstr: _challenge),
        failsWith(AuthFailure.invalidInput),
      );
    }
    for (final challenge in [
      '',
      '|secret',
      'x|secret',
      '0|',
      '0|secret\n',
      '0|secret\r',
      '0|private secret',
      '0|${'x' * 4096}',
    ]) {
      await expectLater(
        api.login(
          username: 'ExampleUser',
          password: _password,
          challstr: challenge,
        ),
        failsWith(AuthFailure.invalidInput),
      );
    }
    await expectLater(
      api.login(username: 'ExampleUser', password: '', challstr: _challenge),
      failsWith(AuthFailure.invalidInput),
    );
    expect(calls, 0);
  });

  test('accepts canonical name spelling with the same user ID', () async {
    final client = FakeAuthHttpClient(
      (_) => response(successBody(username: 'Example User')),
    );
    final api = AuthApiClient(clientFactory: () => client);
    addTearDown(api.dispose);
    final result = await login(api);
    expect(result.username, 'Example User');
    expect(result.userId, 'exampleuser');
  });

  for (final body in [
    '',
    ']null',
    ']{}',
    ']true',
    ']{"curuser":{"loggedin":true,"username":"ExampleUser"},"assertion":123}',
    ']{"curuser":{"loggedin":true,"username":"private|name"},"assertion":"synthetic"}',
    ']{"curuser":{"loggedin":true,"username":"ExampleUser"},"assertion":"synthetic","error":false}',
    ']{"loggedin":true,"username":"ExampleUser","assertion":"synthetic"}',
  ]) {
    test('rejects invalid schema ${jsonEncode(body)}', () async {
      final api = AuthApiClient(
        clientFactory: () => FakeAuthHttpClient((_) => response(body)),
      );
      addTearDown(api.dispose);
      await expectLater(login(api), failsWith(AuthFailure.invalidResponse));
    });
  }

  for (final assertion in [
    '',
    ' synthetic',
    'synthetic ',
    ';;@gmail',
    '<html>private</html>',
    'synthetic\rprivate',
    'synthetic\nprivate',
    'synthetic|private',
    'synthetic\u0000private',
    'synthetic\u2028private',
  ]) {
    test('rejects unsafe assertion ${jsonEncode(assertion)}', () async {
      final api = AuthApiClient(
        clientFactory: () => FakeAuthHttpClient(
          (_) => response(successBody(assertion: assertion)),
        ),
      );
      addTearDown(api.dispose);
      await expectLater(login(api), failsWith(AuthFailure.invalidAssertion));
    });
  }

  test(
    'allows unknown extra fields without returning raw server data',
    () async {
      final data =
          jsonDecode(successBody().substring(1)) as Map<String, dynamic>;
      data['extra'] = {'message': 'private-server-data'};
      final api = AuthApiClient(
        clientFactory: () =>
            FakeAuthHttpClient((_) => response(']${jsonEncode(data)}')),
      );
      addTearDown(api.dispose);
      expect((await login(api)).toString(), isNot(contains('private')));
    },
  );

  test('checks status before reading the body and never retries', () async {
    var listened = false;
    final stream = StreamController<List<int>>(
      onListen: () {
        listened = true;
      },
    );
    final client = FakeAuthHttpClient(
      (_) => http.StreamedResponse(
        stream.stream,
        302,
        headers: {'location': 'https://example.invalid'},
      ),
    );
    final api = AuthApiClient(clientFactory: () => client);
    addTearDown(api.dispose);
    await expectLater(login(api), failsWith(AuthFailure.unexpectedRedirect));
    expect(listened, isFalse);
    expect(client.requests, hasLength(1));
    expect(client.closed, isTrue);
    unawaited(stream.close());
  });

  test('rejects invalid UTF-8 without exposing response bytes', () async {
    final api = AuthApiClient(
      clientFactory: () => FakeAuthHttpClient(
        (_) => http.StreamedResponse(Stream.value([0xff]), 200),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(login(api), failsWith(AuthFailure.invalidResponse));
  });

  test('limits a streaming body even without content-length', () async {
    final client = FakeAuthHttpClient(
      (_) => http.StreamedResponse(
        Stream.fromIterable([List.filled(5, 32), List.filled(6, 32)]),
        200,
      ),
    );
    final api = AuthApiClient(
      clientFactory: () => client,
      maxResponseBytes: 10,
    );
    addTearDown(api.dispose);
    await expectLater(login(api), failsWith(AuthFailure.responseTooLarge));
    expect(client.closed, isTrue);
  });

  test(
    'rejects excessive declared length without subscribing to the body',
    () async {
      var listened = false;
      final stream = StreamController<List<int>>(
        onListen: () {
          listened = true;
        },
      );
      final api = AuthApiClient(
        clientFactory: () => FakeAuthHttpClient(
          (_) =>
              http.StreamedResponse(stream.stream, 200, contentLength: 65537),
        ),
      );
      addTearDown(api.dispose);
      await expectLater(login(api), failsWith(AuthFailure.responseTooLarge));
      expect(listened, isFalse);
      unawaited(stream.close());
    },
  );

  test('accepts a response at the byte limit', () async {
    final body = successBody();
    final api = AuthApiClient(
      clientFactory: () => FakeAuthHttpClient((_) => response(body)),
      maxResponseBytes: utf8.encode(body).length,
    );
    addTearDown(api.dispose);
    expect((await login(api)).assertion, _assertion);
  });

  for (final status in [201, 400, 401, 403, 404]) {
    test('HTTP $status is a safe HTTP failure', () async {
      final api = AuthApiClient(
        clientFactory: () =>
            FakeAuthHttpClient((_) => response('private', status: status)),
      );
      addTearDown(api.dispose);
      await expectLater(login(api), failsWith(AuthFailure.httpFailure));
    });
  }

  test('sanitizes failures from the factory, send and body stream', () async {
    final factories = <http.Client Function()>[
      () => throw StateError('private-factory-secret'),
      () => FakeAuthHttpClient(
        (_) => throw http.ClientException('private-password-secret'),
      ),
      () => FakeAuthHttpClient(
        (_) => http.StreamedResponse(
          Stream.error(StateError('private-body-secret')),
          200,
        ),
      ),
    ];
    for (final factory in factories) {
      final api = AuthApiClient(clientFactory: factory);
      await expectLater(login(api), failsWith(AuthFailure.network));
      await api.dispose();
    }
  });

  test('timeout aborts a request that has not received headers', () async {
    final pendingResponse = Completer<http.StreamedResponse>();
    final aborted = Completer<void>();
    final client = FakeAuthHttpClient((request) {
      (request as http.AbortableRequest).abortTrigger!.then(
        (_) => aborted.complete(),
      );
      return pendingResponse.future;
    });
    final api = AuthApiClient(
      clientFactory: () => client,
      timeout: const Duration(milliseconds: 25),
    );
    addTearDown(api.dispose);
    await expectLater(login(api), failsWith(AuthFailure.timeout));
    await aborted.future;
    expect(client.closed, isTrue);
    pendingResponse.completeError(StateError('private-late-error'));
    await Future<void>.delayed(Duration.zero);
  });

  test('total deadline also cancels a continuously streaming response', () async {
    var cancelled = false;
    Timer? producer;
    late StreamController<List<int>> stream;
    stream = StreamController<List<int>>(
      onListen: () {
        producer = Timer.periodic(
          const Duration(milliseconds: 3),
          (_) => stream.add([32]),
        );
      },
      onCancel: () {
        cancelled = true;
        producer?.cancel();
      },
    );
    final client = FakeAuthHttpClient(
      (_) => http.StreamedResponse(stream.stream, 200),
    );
    final api = AuthApiClient(
      clientFactory: () => client,
      timeout: const Duration(milliseconds: 25),
    );
    addTearDown(api.dispose);
    final result = login(api);
    // Mimic IOClient's abortable response-stream contract in the test adapter.
    final request = client.requests.single as http.AbortableRequest;
    request.abortTrigger!.then((_) {
      if (!cancelled) {
        stream.addError(http.RequestAbortedException(request.url));
      }
    });
    await expectLater(result, failsWith(AuthFailure.timeout));
    await Future<void>.delayed(Duration.zero);
    expect(client.closed, isTrue);
    expect(cancelled, isTrue);
    await stream.close();
  });

  test(
    'cancel rejects the old result; a later login uses a fresh client',
    () async {
      final delayed = Completer<http.StreamedResponse>();
      final clients = <FakeAuthHttpClient>[];
      final api = AuthApiClient(
        clientFactory: () {
          final client = FakeAuthHttpClient(
            (_) =>
                clients.length == 1 ? delayed.future : response(successBody()),
          );
          clients.add(client);
          return client;
        },
      );
      addTearDown(api.dispose);
      final old = login(api);
      final rejected = expectLater(old, failsWith(AuthFailure.cancelled));
      api.cancelPending();
      await rejected;
      expect(clients.first.closed, isTrue);
      final fresh = await login(api);
      delayed.complete(response('private late response'));
      expect(fresh.assertion, _assertion);
      expect(clients, hasLength(2));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'one login at a time; dispose cancels pending work and is terminal',
    () async {
      final delayed = Completer<http.StreamedResponse>();
      final client = FakeAuthHttpClient((_) => delayed.future);
      final api = AuthApiClient(clientFactory: () => client);
      final pending = login(api);
      await expectLater(login(api), throwsStateError);
      final rejected = expectLater(pending, failsWith(AuthFailure.cancelled));
      final disposed = api.dispose();
      expect(identical(disposed, api.dispose()), isTrue);
      await disposed;
      await rejected;
      expect(client.closed, isTrue);
      await expectLater(login(api), throwsStateError);
      delayed.completeError(StateError('private-late-disposal-error'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('cleanup errors do not expose adapter details', () async {
    final client = FakeAuthHttpClient((_) => response(successBody()))
      ..failClose = true;
    final api = AuthApiClient(clientFactory: () => client);
    expect((await login(api)).userId, 'exampleuser');
    await api.dispose();
  });

  test('requires positive limits', () {
    expect(() => AuthApiClient(timeout: Duration.zero), throwsArgumentError);
    expect(() => AuthApiClient(maxResponseBytes: 0), throwsArgumentError);
  });
}
