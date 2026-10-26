import '../server_event.dart';
import '../../battle/state/battle_result.dart';

final class BattleEndEvent extends ServerEvent {
  const BattleEndEvent(super.record, {required this.result});
  final BattleResult result;
}
