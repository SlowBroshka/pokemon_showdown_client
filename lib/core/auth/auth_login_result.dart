/// HTTP login result only. The game server has NOT confirmed this identity.
/// The assertion is secret, connection-bound and must not be logged or persisted.
final class AuthLoginResult {
  const AuthLoginResult({
    required this.username,
    required this.userId,
    required this.assertion,
  });

  final String username;
  final String userId;
  final String assertion;

  @override
  String toString() => 'AuthLoginResult(redacted)';
}
