import 'observed_pokemon.dart';

/// One public switch/drag appearance, NOT a proven unique team member.
/// IDs are local to a BattleState (room + connection epoch), never reused.
final class BattleAppearance {
  BattleAppearance({
    required this.id,
    required this.enteredTurn,
    required this.pokemon,
    Iterable<int> samePresentationIds = const [],
  }) : samePresentationIds = List.unmodifiable(samePresentationIds);

  final int id;
  final int enteredTurn;
  final ObservedPokemon pokemon;

  /// Earlier appearances with identical public ident/details. Even a single
  /// match does not prove identity (Illusion); this is not an exhaustive list.
  final List<int> samePresentationIds;

  BattleAppearance withPokemon(ObservedPokemon value) => BattleAppearance(
    id: id,
    enteredTurn: enteredTurn,
    pokemon: value,
    samePresentationIds: samePresentationIds,
  );

  BattleAppearance retainingReferences(Set<int> retained) => BattleAppearance(
    id: id,
    enteredTurn: enteredTurn,
    pokemon: pokemon,
    samePresentationIds: samePresentationIds.where(retained.contains),
  );
}
