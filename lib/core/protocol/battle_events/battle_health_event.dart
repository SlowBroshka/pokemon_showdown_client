import '../server_event.dart';
import '../../battle/state/battle_health_change.dart';

final class BattleHealthEvent extends ServerEvent {
  BattleHealthEvent(super.record, {required List<BattleHealthChange> changes})
    : changes = List.unmodifiable(changes);
  final List<BattleHealthChange> changes;
}
