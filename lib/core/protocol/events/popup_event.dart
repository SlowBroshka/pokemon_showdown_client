import '../server_event.dart';

/// Raw popup text; the UI may interpret double pipes as line breaks.
final class PopupEvent extends ServerEvent {
  const PopupEvent(super.record, {required this.message});

  final String message;
}
