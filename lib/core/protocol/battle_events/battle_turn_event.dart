import '../server_event.dart';

final class BattleTurnEvent extends ServerEvent {
  const BattleTurnEvent(super.record, {required this.turn});
  final int turn;
}
