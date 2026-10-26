import '../server_event.dart';

final class BattleFaintEvent extends ServerEvent {
  const BattleFaintEvent(super.record, {required this.ident});
  final String ident;
}
