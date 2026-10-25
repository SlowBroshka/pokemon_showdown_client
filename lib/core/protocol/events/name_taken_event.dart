import '../server_event.dart';

final class NameTakenEvent extends ServerEvent {
  const NameTakenEvent(
    super.record, {
    required this.username,
    required this.message,
  });

  /// May be empty when the server rejects a syntactically invalid name.
  final String username;

  final String message;
}
