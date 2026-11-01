import '../requests/pokemon_status.dart';

/// A public status report addressed to an inactive nickname, without species or
/// slot identity. Never rewrites an arbitrary historical appearance or request.
final class BenchStatusObservation {
  BenchStatusObservation({
    required this.ident,
    required this.turn,
    required this.status,
    required this.cured,
    Iterable<int> candidateAppearanceIds = const [],
  }) : candidateAppearanceIds = List.unmodifiable(candidateAppearanceIds);

  final String ident;
  final int turn;
  final PokemonStatus status;
  final bool cured;
  final List<int> candidateAppearanceIds;

  /// A nickname alone cannot exclude a previously unseen team member.
  bool get mayReferToUnseenPokemon => true;

  BenchStatusObservation retainingReferences(Set<int> retained) =>
      BenchStatusObservation(
        ident: ident,
        turn: turn,
        status: status,
        cured: cured,
        candidateAppearanceIds: candidateAppearanceIds.where(retained.contains),
      );
}
