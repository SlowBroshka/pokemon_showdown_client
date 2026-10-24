import '../protocol/server_event.dart';

/// The routing address is explicit, including headerless lobby lifecycle events.
final class RoomEvent {
  const RoomEvent({required this.roomId, required this.event});

  final String roomId;
  final ServerEvent event;
}
