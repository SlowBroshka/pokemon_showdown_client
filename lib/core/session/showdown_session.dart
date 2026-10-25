import 'dart:async';

import '../protocol/client_command.dart';
import '../rooms/room_router.dart';
import '../transport/showdown_transport.dart';
import 'session_update.dart';

export '../rooms/room_info.dart';
export '../transport/transport_exception.dart';
export '../transport/transport_failure.dart';
export '../transport/transport_status.dart';
export 'session_update.dart';

/// Single owner of one transport and router. No Flutter, auth, retry or queue.
/// An injected transport is adopted exclusively and disposed with the session.
final class ShowdownSession {
  ShowdownSession({ShowdownTransport? transport})
    : _transport = transport ?? ShowdownTransport() {
    if (_transport.status != TransportStatus.disconnected) {
      throw StateError('Session requires an unused disconnected transport');
    }
    _router = RoomRouter(_transport);
    _subscription = _router.updates.listen(_receive);
  }

  final ShowdownTransport _transport;
  late final RoomRouter _router;
  late final StreamSubscription<RoomRouterUpdate> _subscription;
  final _updates = StreamController<SessionUpdate>.broadcast();
  int _epoch = 0;
  int _receivedEpoch = 0;
  bool _disposed = false;
  Future<void>? _disconnecting;
  Future<void>? _disposal;

  TransportStatus get status => _transport.status;
  int get connectionEpoch => _epoch;
  Map<String, RoomInfo> get rooms => _router.rooms;
  Stream<Map<String, RoomInfo>> get roomChanges => _router.roomChanges;
  Stream<TransportException> get failures => _transport.failures;

  /// Ordered notifications from subscription time, including obsolete epochs.
  /// Events contain private data: do not log or retain them indiscriminately.
  Stream<SessionUpdate> get updates => _updates.stream;

  Stream<TransportStatus> get statuses => updates
      .where(
        (update) => update.status != null && update.connectionEpoch == _epoch,
      )
      .map((update) => update.status!);

  /// Convenience streams drop obsolete events at delivery time. No replay.
  Stream<SessionUpdate> get globalEvents => updates.where(
    (update) =>
        update.event != null &&
        update.roomId == null &&
        isCurrent(update.connectionEpoch),
  );
  Stream<SessionUpdate> get roomEvents => updates.where(
    (update) =>
        update.event != null &&
        update.roomId != null &&
        isCurrent(update.connectionEpoch),
  );
  Stream<SessionUpdate> eventsForRoom(String id) =>
      roomEvents.where((update) => update.roomId == id);

  /// Connecting is active so an early challenge can be consumed before ready.
  bool isCurrent(int epoch) =>
      !_disposed &&
      epoch > 0 &&
      epoch == _epoch &&
      (status == TransportStatus.connecting ||
          status == TransportStatus.connected);

  Future<void> connect(Uri endpoint) {
    if (_disposed || _disconnecting != null) {
      throw StateError(
        'Session cannot connect during cleanup or after disposal',
      );
    }
    // Synchronous validation failures do not consume an epoch. A failed/cancelled
    // handshake does, as the accepted attempt may already have received data.
    final pending = _transport.connect(endpoint);
    _epoch++;
    return pending;
  }

  /// Callers capture an epoch BEFORE starting asynchronous work (e.g. HTTP).
  /// A stale result cannot send into a new socket, even for the same username.
  void send(ClientCommand command, {required int connectionEpoch}) {
    if (!isCurrent(connectionEpoch)) {
      throw StateError('Command belongs to an inactive connection');
    }
    _transport.send(command);
  }

  Future<void> disconnect() {
    if (_disposed) return _disposal ?? Future.value();
    return _disconnecting ??= _disconnect();
  }

  Future<void> _disconnect() async {
    try {
      await _transport.disconnect();
    } finally {
      _disconnecting = null;
    }
  }

  void _receive(RoomRouterUpdate update) {
    final status = update.status;
    if (status != null) {
      if (status == TransportStatus.connecting) _receivedEpoch++;
      _updates.add(SessionUpdate.status(_receivedEpoch, status));
    } else {
      _updates.add(
        SessionUpdate.event(
          _receivedEpoch,
          update.event!,
          roomId: update.roomId,
        ),
      );
    }
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    // Detach downstream subscriptions before closing their upstream sources.
    // No terminal event is promised after dispose(); status is synchronously
    // invalidated via _disposed and the streams finish when cleanup completes.
    await _subscription.cancel();
    await _router.dispose();
    await _transport.dispose();
    await _updates.close();
  }
}
