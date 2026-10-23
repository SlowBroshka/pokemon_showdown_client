import '../server_event.dart';

/// USER is preserved with rank/status. NAMED does not prove registration.
/// settingsJson is a validated JSON object string, or null for legacy messages.
final class UpdateUserEvent extends ServerEvent {
  const UpdateUserEvent(
    super.record, {
    required this.user,
    required this.named,
    required this.avatar,
    required this.settingsJson,
  });

  final String user;

  final bool named;

  final String avatar;

  final String? settingsJson;
}
