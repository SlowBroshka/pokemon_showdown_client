import '../protocol/server_event.dart';
import '../transport/transport_status.dart';

/// One ordered lifecycle notification or routed event, with its original epoch.
/// A null roomId on an event denotes the global route, not the last active room.
final class SessionUpdate {
  /// Source progress only: no protocol event or lifecycle change.
  const SessionUpdate.emptyFrame(this.connectionEpoch, {required this.sequence})
    : status = null,
      event = null,
      roomId = null;

  const SessionUpdate.status(
    this.connectionEpoch,
    TransportStatus value, {
    this.sequence = 0,
  }) : status = value,
       event = null,
       roomId = null;

  const SessionUpdate.event(
    this.connectionEpoch,
    ServerEvent value, {
    this.roomId,
    this.sequence = 0,
  }) : event = value,
       status = null;

  final int connectionEpoch;
  final TransportStatus? status;
  final ServerEvent? event;
  final String? roomId;
  final int sequence;
}
