import 'auth_failure.dart';
import 'auth_phase.dart';

/// Public snapshot. No password, challenge, assertion or arbitrary server text.
final class AuthState {
  const AuthState(this.phase, {this.error, this.username, this.userId});

  final AuthPhase phase;
  final AuthFailure? error;
  final String? username;
  final String? userId;

  @override
  String toString() => 'AuthState(${phase.name}, ${error?.name})';
}
