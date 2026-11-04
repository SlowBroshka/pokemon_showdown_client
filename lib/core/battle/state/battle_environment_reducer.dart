import '../../protocol/battle_events/battle_environment_event.dart';
import 'battle_environment.dart';

/// Null signals an inconsistent observation. No partial update escapes.
BattleEnvironment? reduceEnvironment(
  BattleEnvironment state,
  BattleEnvironmentEvent event,
  int turn,
) {
  final id = event.condition;
  EnvironmentCondition observation() => EnvironmentCondition(
    id: id!,
    startedTurn: turn,
    sourceEffect: event.sourceEffect,
    sourceIdent: event.sourceIdent,
  );
  switch (event.operation) {
    case EnvironmentOperation.weather:
      if (id == 'none') return state.copyWith(clearWeather: true);
      if (event.upkeep) {
        if (state.weather?.id != id) return null;
        return state.copyWith(
          weather: state.weather!.withProgress(upkeepTurn: turn),
        );
      }
      return state.copyWith(weather: observation());
    case EnvironmentOperation.fieldStart:
      if (battleTerrains.contains(id)) {
        return state.copyWith(terrain: observation());
      }
      return state.copyWith(fields: {...state.fields, id!: observation()});
    case EnvironmentOperation.fieldEnd:
      if (battleTerrains.contains(id)) {
        // A late or repeated end must never remove a different current terrain.
        return state.terrain?.id == id
            ? state.copyWith(clearTerrain: true)
            : state;
      }
      return state.copyWith(fields: {...state.fields}..remove(id));
    case EnvironmentOperation.fieldActivate:
      final entries = [
        ...state.activations,
        FieldActivation(id: id!, turn: turn),
      ];
      return state.copyWith(
        activations: entries.length <= maxFieldActivations
            ? entries
            : entries.sublist(entries.length - maxFieldActivations),
      );
    case EnvironmentOperation.sideStart:
    case EnvironmentOperation.sideEnd:
      final side = {...(event.sideId == 'p1' ? state.p1 : state.p2)};
      if (event.operation == EnvironmentOperation.sideEnd) {
        side.remove(id);
      } else {
        final previous = side[id];
        final maxLayers = battleSideConditions[id]!;
        if (maxLayers > 1 && previous != null) {
          if (previous.layers >= maxLayers) return null;
          side[id!] = previous.withProgress(layers: previous.layers + 1);
        } else {
          side[id!] = observation();
        }
      }
      return event.sideId == 'p1'
          ? state.copyWith(p1: side)
          : state.copyWith(p2: side);
    case EnvironmentOperation.swapSides:
      // The complete supported registry is in upstream Court Change's allowlist.
      return state.copyWith(p1: state.p2, p2: state.p1);
    case EnvironmentOperation.courtChangeActivation:
      return state; // Already applied by -swapsideconditions; never swap twice.
  }
}
