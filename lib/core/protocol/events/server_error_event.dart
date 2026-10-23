import '../server_event.dart';

final class ServerErrorEvent extends ServerEvent {
  const ServerErrorEvent(super.record, {required this.message});

  final String message;
}
