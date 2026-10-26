import '../requests/pokemon_status.dart';

/// Numbers as reported in a public event; maximum is not inferred to be exact.
final class BattleHealth {
  const BattleHealth({
    required this.hp,
    required this.maxHp,
    required this.fainted,
    this.status,
  });
  final int hp;
  final int? maxHp;
  final bool fainted;
  final PokemonStatus? status;
  BattleHealth withStatus(PokemonStatus? value) =>
      BattleHealth(hp: hp, maxHp: maxHp, fainted: fainted, status: value);
}
