import 'dart:async';

/// Internal bookkeeping only; never retains passwords or assertions.
final class AuthAttempt {
  AuthAttempt(this.id, this.epoch, this.challengeRevision);

  final int id;
  final int epoch;
  final int challengeRevision;
  final completed = Completer<void>();
  int? sentAfterSequence;
  String? username;
  String? userId;
}
