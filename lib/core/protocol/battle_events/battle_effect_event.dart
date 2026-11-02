import '../server_event.dart';

/// Validated protocol operation, with no simulator-derived predictions.
final class BattleEffectEvent extends ServerEvent {
  BattleEffectEvent(
    super.record, {
    required this.operation,
    required List<String> arguments,
  }) : arguments = List.unmodifiable(arguments);
  final String operation;
  final List<String> arguments;
}
