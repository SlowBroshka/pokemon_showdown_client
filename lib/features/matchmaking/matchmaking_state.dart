enum MatchmakingPhase {
  unavailable,
  idle,
  submitting,
  searching,
  cancelling,
  stoppedObserved,
  awaitingBattle,
  inBattle,
  outcomeUnknown,
  disconnected,
}

/// Safe categories only; never retains raw server or exception text.
enum MatchmakingNotice {
  serverNotice,
  sendFailed,
  timeout,
  conflict,
  invalidSearchSnapshot,
}

final class MatchmakingState {
  const MatchmakingState(this.phase, {this.attemptToken, this.notice});

  final MatchmakingPhase phase;
  final Object? attemptToken;
  final MatchmakingNotice? notice;
}
