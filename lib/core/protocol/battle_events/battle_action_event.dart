import '../server_event.dart';

final class BattleActionEvent extends ServerEvent {
  const BattleActionEvent(
    super.record, {
    required this.actor,
    required this.action,
    required this.cannotAct,
    this.target,
    this.attemptedMove,
  });
  final String actor;
  final String action;
  final bool cannotAct;
  final String? target;
  final String? attemptedMove;
}
