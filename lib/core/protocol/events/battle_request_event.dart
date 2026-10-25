import '../../battle/requests/battle_request.dart';
import '../server_event.dart';

/// Always emitted for a room request, including clear and rejected payloads.
/// Consumers must replace the previous snapshot even when this one is invalid.
final class BattleRequestEvent extends ServerEvent {
  const BattleRequestEvent(super.record, {required this.request});
  final BattleRequest request;
}
