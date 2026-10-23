import '../server_event.dart';

final class NameTakenEvent extends ServerEvent {
  const NameTakenEvent(
    super.record, {
    required this.username,
    required this.message,
  });

  final String username;

  final String message;
}
