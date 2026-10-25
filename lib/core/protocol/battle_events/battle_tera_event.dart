import '../server_event.dart';

final class BattleTeraEvent extends ServerEvent {
  const BattleTeraEvent(
    super.record, {
    required this.ident,
    required this.teraType,
  });
  final String ident;
  final String teraType;
}
