/// Structured action only; excludes raw records, private requests and HTML.
final class BattleLogEntry {
  const BattleLogEntry({
    required this.turn,
    required this.actor,
    required this.action,
    required this.cannotAct,
    this.target,
    this.attemptedMove,
  });
  final int turn;
  final String actor;
  final String action;
  final bool cannotAct;
  final String? target;
  final String? attemptedMove;
}
