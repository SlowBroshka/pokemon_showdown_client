import 'pokemon_condition.dart';

final class RequestPokemon {
  RequestPokemon({
    required this.slot,
    required this.ident,
    required this.details,
    required this.condition,
    required this.active,
    required List<String> moves,
    required Map<String, int> stats,
    this.item,
    this.ability,
    this.baseAbility,
    this.teraType,
    this.terastallized,
  }) : moves = List.unmodifiable(moves),
       stats = Map.unmodifiable(stats);
  final int slot;
  final String ident;
  final String details;
  final PokemonCondition condition;
  final bool active;
  final List<String> moves;
  final Map<String, int> stats;
  // null means undisclosed; an empty string means explicitly absent.
  final String? item;
  final String? ability;
  final String? baseAbility;
  final String? teraType;
  final String? terastallized;
}
