import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_exception.dart';
import 'auth_failure.dart';
import 'auth_login_result.dart';
import 'auth_response_decoder.dart';
import 'auth_user_id.dart';

export 'auth_exception.dart';
export 'auth_failure.dart';
export 'auth_login_result.dart';

/// Password login against the fixed trusted service. No WSS, cookies or retries.
/// A fresh owned HTTP client is created and closed for each request. An injected
/// factory is a trusted test seam and must return a fresh, abort-capable client.
final class AuthApiClient {
  AuthApiClient({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 64 * 1024,
  }) : _clientFactory = clientFactory ?? http.Client.new {
    if (timeout <= Duration.zero || maxResponseBytes <= 0) {
      throw ArgumentError('Auth limits must be positive');
    }
  }

  static final endpoint = Uri.https(
    'play.pokemonshowdown.com',
    '/~~showdown/action.php',
  );
  final http.Client Function() _clientFactory;
  final Duration timeout;
  final int maxResponseBytes;
  void Function(AuthFailure)? _stop;
  Future<void>? _pendingCleanup;
  Future<void>? _disposal;
  bool _disposed = false;

  Future<AuthLoginResult> login({
    required String username,
    required String password,
    required String challstr,
  }) async {
    if (_disposed || _stop != null) {
      throw StateError(
        'Auth client is disposed or already has a pending login',
      );
    }
    final userId = authUserId(username);
    if (userId == null ||
        password.isEmpty ||
        challstr.length > 4096 ||
        RegExp(r'^[0-9]+\|[^\s\x00-\x1f\x7f-\x9f]+$').stringMatch(challstr) !=
            challstr) {
      throw const AuthException(AuthFailure.invalidInput);
    }
    final abort = Completer<void>();
    final stopped = Completer<AuthLoginResult>();
    final cleanup = Completer<void>();
    _pendingCleanup = cleanup.future;
    _stop = (failure) {
      if (!stopped.isCompleted) {
        stopped.completeError(AuthException(failure));
      }
      if (!abort.isCompleted) abort.complete();
    };
    final timer = Timer(timeout, () => _stop?.call(AuthFailure.timeout));
    http.Client? client;
    try {
      client = _clientFactory();
      final request =
          http.AbortableRequest('POST', endpoint, abortTrigger: abort.future)
            ..followRedirects = false
            ..maxRedirects = 0
            ..encoding = utf8
            ..bodyFields = {
              'act': 'login',
              'name': username,
              'pass': password,
              'challstr': challstr,
            };
      return await Future.any([
        _perform(client, request, userId),
        stopped.future,
      ]);
    } on AuthException {
      rethrow;
    } catch (_) {
      // No request/response, underlying exception or server message is retained.
      throw const AuthException(AuthFailure.network);
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      try {
        client?.close();
      } catch (_) {
        // Best-effort cleanup must not leak an adapter's exception contents.
      }
      _stop = null;
      _pendingCleanup = null;
      cleanup.complete();
    }
  }

  Future<AuthLoginResult> _perform(
    http.Client client,
    http.BaseRequest request,
    String requestedUserId,
  ) async {
    final response = await client.send(request);
    checkAuthHttpStatus(response.statusCode);
    if ((response.contentLength ?? 0) > maxResponseBytes) {
      throw const AuthException(AuthFailure.responseTooLarge);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const AuthException(AuthFailure.responseTooLarge);
      }
      bytes.addAll(chunk);
    }
    final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      throw const AuthException(AuthFailure.invalidResponse);
    }
    return decodeAuthLoginResponse(body, requestedUserId: requestedUserId);
  }

  /// Cancels this attempt only. Await the pending login before starting another.
  void cancelPending() => _stop?.call(AuthFailure.cancelled);

  /// Terminal, idempotent disposal; completes after owned resources are closed.
  Future<void> dispose() {
    _disposed = true;
    cancelPending();
    return _disposal ??= (_pendingCleanup ?? Future.value());
  }
}
