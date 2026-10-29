import '../../matchmaking/search/search_snapshot_result.dart';
import '../server_event.dart';

/// Global updates include malformed results so callers cannot keep treating an
/// older valid snapshot as confirmation of the current queue state.
final class UpdateSearchEvent extends ServerEvent {
  const UpdateSearchEvent(super.record, {required this.result});
  final SearchSnapshotResult result;
}
