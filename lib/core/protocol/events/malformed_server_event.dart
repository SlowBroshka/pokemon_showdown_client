import '../server_event.dart';

/// A structural failure. reason never includes the incoming payload.
final class MalformedServerEvent extends ServerEvent {
  const MalformedServerEvent(super.record, {required this.reason});

  final String reason;
}
