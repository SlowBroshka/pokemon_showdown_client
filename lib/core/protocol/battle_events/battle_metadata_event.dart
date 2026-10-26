import '../server_event.dart';
import 'battle_metadata_kind.dart';

final class BattleMetadataEvent extends ServerEvent {
  const BattleMetadataEvent(
    super.record, {
    required this.kind,
    this.text,
    this.number,
    this.sideId,
  });
  final BattleMetadataKind kind;
  final String? text;
  final int? number;
  final String? sideId;
}
