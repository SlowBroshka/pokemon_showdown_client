import 'battle_choice.dart';

/// Immutable context captured before any asynchronous UI work.
final class CapturedBattleChoice {
  const CapturedBattleChoice({
    required this.roomId,
    required this.connectionEpoch,
    required this.requestRevision,
    required this.rqid,
    required this.choice,
    this.contextToken,
  });
  final String roomId;
  final int connectionEpoch;
  final int requestRevision;
  final int? rqid;
  final BattleChoice choice;

  /// Identity of the controller that captured this choice, including room visits.
  final Object? contextToken;
}
