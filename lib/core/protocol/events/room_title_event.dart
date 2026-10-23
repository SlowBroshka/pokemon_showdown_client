import '../server_event.dart';

final class RoomTitleEvent extends ServerEvent {
  const RoomTitleEvent(super.record, {required this.title});

  final String title;
}
