import 'pokemon_status.dart';

/// Private HP reported by request.side, not the opponent's public HP scale.
final class PokemonCondition {
  const PokemonCondition({
    required this.hp,
    required this.maxHp,
    required this.fainted,
    this.status,
  });
  final int hp;
  final int? maxHp;
  final bool fainted;
  final PokemonStatus? status;
}
