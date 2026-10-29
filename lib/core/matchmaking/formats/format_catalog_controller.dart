import 'dart:async';

import '../../protocol/events/formats_event.dart';
import '../../session/showdown_session.dart';
import 'format_availability.dart';
import 'format_catalog.dart';
import 'format_support_policy.dart';

/// Attach before connecting. Owns no socket and never sends commands.
final class FormatCatalogController {
  FormatCatalogController({required ShowdownSession session})
    : _session = session {
    _subscription = session.updates.listen(_receive, onDone: _invalidate);
  }

  final ShowdownSession _session;

  /// Shared session identity for composition checks; ownership stays unchanged.
  ShowdownSession get session => _session;
  late final StreamSubscription<SessionUpdate> _subscription;
  final _changes = StreamController<void>.broadcast();
  FormatCatalog? _catalog;
  int _epoch = 0;
  int _seenSequence = -1;
  int _settledSequence = -1;
  Timer? _settleTimer;
  bool _disposed = false;
  Future<void>? _disposal;

  FormatCatalog? get catalog => _catalog;
  Stream<void> get changes => _changes.stream;

  /// Consult live source progress too: pending updates cannot authorize a start.
  bool get fresh =>
      !_disposed &&
      _catalog != null &&
      _session.status == TransportStatus.connected &&
      _session.isCurrent(_epoch) &&
      _seenSequence == _session.latestUpdateSequence &&
      _settledSequence == _seenSequence;

  FormatAvailability availability(
    String formatId, {
    bool experimentalEnabled = false,
  }) => formatAvailability(
    _catalog,
    formatId: formatId,
    fresh: fresh,
    experimentalEnabled: experimentalEnabled,
  );

  void _receive(SessionUpdate update) {
    if (_disposed || update.connectionEpoch != _session.connectionEpoch) return;
    _seenSequence = update.sequence;
    _settledSequence = -1;
    _settleTimer?.cancel();
    // Drain all records sharing the source frame before making it actionable.
    _settleTimer = Timer(Duration.zero, () {
      if (_disposed) return;
      _settledSequence = _seenSequence;
      _changes.add(null);
    });
    if (update.status != null) {
      if (update.status == TransportStatus.connecting ||
          update.status == TransportStatus.disconnected ||
          update.status == TransportStatus.disposed) {
        _invalidate();
      } else {
        _changes.add(null);
      }
      return;
    }
    if (!_session.isCurrent(update.connectionEpoch)) return;
    final event = update.event;
    if (update.roomId == null && event is FormatsEvent) {
      _epoch = update.connectionEpoch;
      _catalog = event.catalog;
    }
    // Consumers re-check after delivery, including unrelated source progress.
    _changes.add(null);
  }

  void _invalidate() {
    if (_disposed) return;
    _catalog = null;
    _epoch = 0;
    _changes.add(null);
  }

  Future<void> dispose() {
    if (_disposed) return _disposal!;
    _disposed = true;
    _settleTimer?.cancel();
    _catalog = null;
    return _disposal = _close();
  }

  Future<void> _close() async {
    await _subscription.cancel();
    await _changes.close();
  }
}
