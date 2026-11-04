import '../server_event.dart';

enum EnvironmentOperation {
  weather,
  fieldStart,
  fieldEnd,
  fieldActivate,
  sideStart,
  sideEnd,
  swapSides,
  courtChangeActivation,
}

final class BattleEnvironmentEvent extends ServerEvent {
  const BattleEnvironmentEvent(
    super.record, {
    required this.operation,
    this.condition,
    this.sideId,
    this.actor,
    this.upkeep = false,
    this.sourceEffect,
    this.sourceIdent,
  });
  final EnvironmentOperation operation;
  final String? condition;
  final String? sideId;
  final String? actor;
  final bool upkeep;
  final String? sourceEffect;
  final String? sourceIdent;
}
