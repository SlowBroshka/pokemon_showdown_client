/// Publicly reported stages only; never used to compute legal choices or damage.
const battleStats = {'atk', 'def', 'spa', 'spd', 'spe', 'accuracy', 'evasion'};

/// Reviewed against the pinned simulator. Unknown effects remain unsupported.
const persistentEffects = {
  'substitute',
  'confusion',
  'aquaring',
  'ingrain',
  'leechseed',
  'taunt',
  'encore',
  'disable',
};
const passableEffects = {
  'substitute',
  'confusion',
  'aquaring',
  'ingrain',
  'leechseed',
  'taunt',
};

final class PokemonEffects {
  const PokemonEffects.empty() : boosts = const {}, volatiles = const {};
  PokemonEffects({
    Map<String, int> boosts = const {},
    Map<String, String?> volatiles = const {},
  }) : boosts = Map.unmodifiable(boosts),
       volatiles = Map.unmodifiable(volatiles);

  /// Missing stages are zero; effect values hold optional public parameters.
  final Map<String, int> boosts;
  final Map<String, String?> volatiles;
  PokemonEffects without(Set<String> names) => PokemonEffects(
    boosts: boosts,
    volatiles: {...volatiles}..removeWhere((key, _) => names.contains(key)),
  );
  PokemonEffects transferred(String source) => PokemonEffects(
    boosts: source == 'move: Baton Pass' ? boosts : const {},
    volatiles: Map.fromEntries(
      volatiles.entries.where(
        (entry) => source == 'move: Shed Tail'
            ? entry.key == 'substitute'
            : passableEffects.contains(entry.key),
      ),
    ),
  );
}
