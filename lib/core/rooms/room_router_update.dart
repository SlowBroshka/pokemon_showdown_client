import '../protocol/server_event.dart';
import '../transport/transport_status.dart';

/// Routed events and lifecycle changes in the transport's original order.
final class RoomRouterUpdate {
  const RoomRouterUpdate.status(TransportStatus value)
    : status = value,
      event = null,
      roomId = null;

  const RoomRouterUpdate.event(ServerEvent value, {this.roomId})
    : event = value,
      status = null;

  final TransportStatus? status;
  final ServerEvent? event;
  final String? roomId;
}
