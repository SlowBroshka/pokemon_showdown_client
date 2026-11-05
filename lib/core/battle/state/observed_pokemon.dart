import 'pokemon_traits.dart';
import 'battle_health.dart';
import 'pokemon_effects.dart';

final class ObservedPokemon {
  const ObservedPokemon({
    required this.ident,
    required this.details,
    required this.health,
    this.teraType,
    this.effects = const PokemonEffects.empty(),
    this.traits = const PokemonTraits(),
  });
  final PokemonEffects effects;
  final PokemonTraits traits;
  final String ident;
  final String details;
  final BattleHealth health;
  final String? teraType;
  String get sideId => ident.substring(0, 2);
  ObservedPokemon withHealth(BattleHealth value) => ObservedPokemon(
    ident: ident,
    details: details,
    health: value,
    teraType: teraType,
    effects: effects,
    traits: traits,
  );
  ObservedPokemon withTera(String value) => ObservedPokemon(
    ident: ident,
    details: details,
    health: health,
    teraType: value,
    effects: effects,
    traits: traits,
  );
  ObservedPokemon withEffects(PokemonEffects value) => ObservedPokemon(
    ident: ident,
    details: details,
    health: health,
    teraType: teraType,
    effects: value,
    traits: traits,
  );
  ObservedPokemon withTraits(PokemonTraits value) => ObservedPokemon(
    ident: ident,
    details: details,
    health: health,
    teraType: teraType,
    effects: effects,
    traits: value,
  );
}
