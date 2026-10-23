import '../server_event.dart';

final class RoomInitEvent extends ServerEvent {
  const RoomInitEvent(super.record, {required this.roomType});

  final String roomType;
}
