import 'battle_request_kind.dart';
import 'request_active.dart';
import 'request_side.dart';

/// A complete, immutable decoded snapshot, never an incremental update.
/// Availability is only local to this request, not permission to send a command.
final class BattleRequest {
  const BattleRequest({
    required this.kind,
    this.rqid,
    this.noCancel = false,
    this.side,
    this.active,
    this.reason,
  });
  final BattleRequestKind kind;
  final int? rqid;
  final bool noCancel;
  final RequestSide? side;
  final RequestActive? active;

  /// Fixed diagnostic category; never contains input text.
  final String? reason;

  List<int> get moveSlots => kind == BattleRequestKind.move
      ? List.unmodifiable(
          active!.moves.where((m) => m.available).map((m) => m.slot),
        )
      : const [];
  List<int> get switchSlots {
    if (kind != BattleRequestKind.move &&
        kind != BattleRequestKind.switchRequest) {
      return const [];
    }
    if (kind == BattleRequestKind.move && active!.trapped) return const [];
    return List.unmodifiable(
      side!.pokemon
          .where((p) => !p.active && !p.condition.fainted)
          .map((p) => p.slot),
    );
  }

  bool get canTerastallize =>
      kind == BattleRequestKind.move &&
      active!.canTerastallize != null &&
      moveSlots.isNotEmpty;
}
