import 'battle_health.dart';

final class BattleHealthChange {
  const BattleHealthChange({required this.ident, required this.health});
  final String ident;
  final BattleHealth health;
}
