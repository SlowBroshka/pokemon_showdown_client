/// Immutable metadata, not a battle-state projection.
final class RoomInfo {
  const RoomInfo({
    required this.id,
    required this.type,
    this.title,
    this.isStale = false,
  });

  final String id;
  final String type;
  final String? title;
  final bool isStale;
}
