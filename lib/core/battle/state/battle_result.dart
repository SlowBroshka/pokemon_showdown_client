final class BattleResult {
  const BattleResult.win(this.winner) : isTie = false;
  const BattleResult.tie() : winner = null, isTie = true;
  final String? winner;
  final bool isTie;
}
