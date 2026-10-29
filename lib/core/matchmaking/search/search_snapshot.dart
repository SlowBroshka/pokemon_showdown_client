/// Account-wide server state, not acknowledgement of a particular command.
final class SearchSnapshot {
  SearchSnapshot({
    required List<String> searching,
    required Map<String, String>? games,
  }) : searching = List.unmodifiable(searching),
       games = games == null ? null : Map.unmodifiable(games);

  final List<String> searching;

  /// Includes non-battle games. Titles are untrusted plain text.
  final Map<String, String>? games;
}
