final class BattlePlayer {
  const BattlePlayer({
    required this.sideId,
    required this.name,
    this.avatar,
    this.rating,
  });
  final String sideId;
  final String name;
  final String? avatar;
  final String? rating;
}
