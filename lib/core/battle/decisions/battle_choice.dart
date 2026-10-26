/// Singles choices only. Legality is checked against the current request.
final class BattleChoice {
  const BattleChoice.move(this.slot, {this.terastallize = false})
    : isMove = true;
  const BattleChoice.switchTo(this.slot) : isMove = false, terastallize = false;

  final int slot;
  final bool isMove;
  final bool terastallize;
}
