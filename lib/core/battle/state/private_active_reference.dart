/// Association valid only for one request revision and public appearance.
/// A request slot is not a persistent identity and does not enter public data.
final class PrivateActiveReference {
  const PrivateActiveReference({
    required this.sideId,
    required this.requestRevision,
    required this.requestSlot,
    required this.appearanceId,
  });
  final String sideId;
  final int requestRevision;
  final int requestSlot;
  final int appearanceId;
}
