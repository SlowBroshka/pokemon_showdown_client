import 'dart:convert';

import 'search_snapshot.dart';
import 'search_snapshot_result.dart';

final _invalidFormatId = RegExp(r'[^a-z0-9]');
final _invalidRoomId = RegExp(r'[^a-z0-9-]');

/// Decodes the JSON after global updatesearch, without inferring search outcome.
SearchSnapshotResult decodeSearchSnapshot(String data) {
  const malformed = SearchSnapshotResult.malformed();
  final dynamic decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    return malformed;
  }
  if (decoded is! Map<String, dynamic> ||
      !decoded.containsKey('searching') ||
      !decoded.containsKey('games')) {
    return malformed;
  }
  final rawSearches = decoded['searching'];
  if (rawSearches is! List) return malformed;
  final searching = <String>[];
  final seen = <String>{};
  for (final value in rawSearches) {
    if (value is! String ||
        value.isEmpty ||
        _invalidFormatId.hasMatch(value) ||
        !seen.add(value)) {
      return malformed;
    }
    searching.add(value);
  }
  final rawGames = decoded['games'];
  Map<String, String>? games;
  if (rawGames != null) {
    if (rawGames is! Map<String, dynamic>) return malformed;
    games = {};
    for (final entry in rawGames.entries) {
      if (entry.key.isEmpty ||
          _invalidRoomId.hasMatch(entry.key) ||
          entry.value is! String) {
        return malformed;
      }
      games[entry.key] = entry.value as String;
    }
  }
  return SearchSnapshotResult.valid(
    SearchSnapshot(searching: searching, games: games),
  );
}
