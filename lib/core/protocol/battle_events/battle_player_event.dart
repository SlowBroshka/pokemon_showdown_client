import '../server_event.dart';
import '../../battle/state/battle_player.dart';

final class BattlePlayerEvent extends ServerEvent {
  const BattlePlayerEvent(super.record, {required this.player});
  final BattlePlayer player;
}
