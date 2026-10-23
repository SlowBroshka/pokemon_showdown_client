import '../server_event.dart';

final class PlainTextEvent extends ServerEvent {
  const PlainTextEvent(super.record, {required this.text});

  final String text;
}
