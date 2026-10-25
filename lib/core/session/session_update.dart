import '../protocol/server_event.dart';
import '../transport/transport_status.dart';

/// One ordered lifecycle notification or routed event, with its original epoch.
/// A null roomId on an event denotes the global route, not the last active room.
final class SessionUpdate {
  const SessionUpdate.status(this.connectionEpoch, TransportStatus value)
    : status = value,
      event = null,
      roomId = null;

  const SessionUpdate.event(
    this.connectionEpoch,
    ServerEvent value, {
    this.roomId,
  }) : event = value,
       status = null;

  final int connectionEpoch;
  final TransportStatus? status;
  final ServerEvent? event;
  final String? roomId;
}
