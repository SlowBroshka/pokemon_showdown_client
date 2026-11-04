/// Reviewed Gen 9 singles protocol identifiers. Unknown effects fail closed.
const battleWeather = {'raindance', 'sunnyday', 'sandstorm', 'snowscape'};
const battleTerrains = {
  'electricterrain',
  'grassyterrain',
  'mistyterrain',
  'psychicterrain',
};
const battleFieldConditions = {
  'gravity',
  'trickroom',
  'magicroom',
  'wonderroom',
};

/// Every supported side condition is transferable by Court Change in the pin.
const battleSideConditions = {
  'spikes': 3,
  'toxicspikes': 2,
  'stealthrock': 1,
  'stickyweb': 1,
  'reflect': 1,
  'lightscreen': 1,
  'auroraveil': 1,
  'mist': 1,
  'safeguard': 1,
  'tailwind': 1,
};
const battleFieldActivations = {'perishsong', 'teatime'};
const maxFieldActivations = 50;

/// An observation, not a duration estimate or effective damage modifier.
final class EnvironmentCondition {
  const EnvironmentCondition({
    required this.id,
    required this.startedTurn,
    this.layers = 1,
    this.sourceEffect,
    this.sourceIdent,
    this.lastUpkeepTurn,
  });
  final String id;
  final int startedTurn;
  final int layers;
  final String? sourceEffect;

  /// Public protocol label, not a stable Pokemon identity or private roster link.
  final String? sourceIdent;
  final int? lastUpkeepTurn;
  EnvironmentCondition withProgress({int? layers, int? upkeepTurn}) =>
      EnvironmentCondition(
        id: id,
        startedTurn: startedTurn,
        layers: layers ?? this.layers,
        sourceEffect: sourceEffect,
        sourceIdent: sourceIdent,
        lastUpkeepTurn: upkeepTurn ?? lastUpkeepTurn,
      );
}

final class FieldActivation {
  const FieldActivation({required this.id, required this.turn});
  final String id;
  final int turn;
}

/// Room/epoch-owned environment, independent of active Pokemon appearances.
final class BattleEnvironment {
  BattleEnvironment({
    this.weather,
    this.terrain,
    Map<String, EnvironmentCondition> fields = const {},
    Map<String, EnvironmentCondition> p1 = const {},
    Map<String, EnvironmentCondition> p2 = const {},
    List<FieldActivation> activations = const [],
  }) : fields = Map.unmodifiable(fields),
       p1 = Map.unmodifiable(p1),
       p2 = Map.unmodifiable(p2),
       activations = List.unmodifiable(activations);
  final EnvironmentCondition? weather;
  final EnvironmentCondition? terrain;
  final Map<String, EnvironmentCondition> fields;
  final Map<String, EnvironmentCondition> p1;
  final Map<String, EnvironmentCondition> p2;

  /// Bounded observations; these are not persistent field conditions.
  final List<FieldActivation> activations;
  BattleEnvironment copyWith({
    EnvironmentCondition? weather,
    bool clearWeather = false,
    EnvironmentCondition? terrain,
    bool clearTerrain = false,
    Map<String, EnvironmentCondition>? fields,
    Map<String, EnvironmentCondition>? p1,
    Map<String, EnvironmentCondition>? p2,
    List<FieldActivation>? activations,
  }) => BattleEnvironment(
    weather: clearWeather ? null : weather ?? this.weather,
    terrain: clearTerrain ? null : terrain ?? this.terrain,
    fields: fields ?? this.fields,
    p1: p1 ?? this.p1,
    p2: p2 ?? this.p2,
    activations: activations ?? this.activations,
  );
}
