import '../server_event.dart';

final class UnknownServerEvent extends ServerEvent {
  const UnknownServerEvent(
    super.record, {
    required this.eventType,
    required this.data,
  });

  final String eventType;

  final String data;
}
