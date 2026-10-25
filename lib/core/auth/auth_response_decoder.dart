import 'dart:convert';

import '../protocol/commands/command_validation.dart';
import 'auth_exception.dart';
import 'auth_failure.dart';
import 'auth_login_result.dart';
import 'auth_user_id.dart';

void checkAuthHttpStatus(int status) {
  if (status >= 300 && status < 400) {
    throw const AuthException(AuthFailure.unexpectedRedirect);
  }
  if (status == 429) throw const AuthException(AuthFailure.rateLimited);
  if (status >= 500 && status < 600) {
    throw const AuthException(AuthFailure.serviceUnavailable);
  }
  if (status != 200) throw const AuthException(AuthFailure.httpFailure);
}

/// Pure boundary decoder. Raw bodies/errors never escape in exceptions.
AuthLoginResult decodeAuthLoginResponse(
  String body, {
  required String requestedUserId,
}) {
  if (!body.startsWith(']')) {
    throw const AuthException(AuthFailure.invalidResponse);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body.substring(1));
  } on FormatException {
    throw const AuthException(AuthFailure.invalidResponse);
  }
  if (decoded is! Map<String, dynamic>) {
    throw const AuthException(AuthFailure.invalidResponse);
  }
  for (final key in ['actionerror', 'error']) {
    if (!decoded.containsKey(key)) continue;
    if (decoded[key] is String) {
      throw const AuthException(AuthFailure.loginRejected);
    }
    throw const AuthException(AuthFailure.invalidResponse);
  }
  final user = decoded['curuser'];
  if (user is! Map<String, dynamic>) {
    throw const AuthException(AuthFailure.invalidResponse);
  }
  if (user['loggedin'] == false) {
    throw const AuthException(AuthFailure.loginRejected);
  }
  final name = user['username'];
  final assertion = decoded['assertion'];
  if (user['loggedin'] != true ||
      name is! String ||
      authUserId(name) != requestedUserId ||
      assertion is! String) {
    throw const AuthException(AuthFailure.invalidResponse);
  }
  if (assertion.startsWith(';') || assertion.contains('<')) {
    throw const AuthException(AuthFailure.invalidAssertion);
  }
  try {
    validateCommandField(assertion, 'assertion');
  } on ArgumentError {
    throw const AuthException(AuthFailure.invalidAssertion);
  }
  return AuthLoginResult(
    username: name,
    userId: requestedUserId,
    assertion: assertion,
  );
}
