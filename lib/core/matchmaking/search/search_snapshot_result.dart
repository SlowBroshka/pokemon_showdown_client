import 'search_snapshot.dart';

/// A malformed update has no snapshot: it cannot masquerade as an empty queue.
final class SearchSnapshotResult {
  const SearchSnapshotResult.valid(SearchSnapshot value) : snapshot = value;
  const SearchSnapshotResult.malformed() : snapshot = null;

  final SearchSnapshot? snapshot;
  bool get isValid => snapshot != null;
}
