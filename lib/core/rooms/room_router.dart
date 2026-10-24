import 'dart:async';

import '../protocol/server_event_decoder.dart';
import '../protocol/server_message.dart';
import '../transport/showdown_transport.dart';
import 'room_event.dart';
import 'room_info.dart';

export 'room_event.dart';
export 'room_info.dart';

/// Owns its subscriptions, but not the transport. Attach before connecting.
/// Streams are broadcast notifications, without replay or retained event logs.
final class RoomRouter {
  RoomRouter(this._transport) {
    _status = _transport.status;
    _subscription = _transport.updates.listen((update) {
      if (_disposed) return;
      final status = update.status;
      if (status != null) {
        _status = status;
        if (status != TransportStatus.connected) _markStale();
      } else {
        _receive(update.message!);
      }
    }, onDone: _markStale);
  }

  final ShowdownTransport _transport;
  final _globalEvents = StreamController<ServerEvent>.broadcast();
  final _roomEvents = StreamController<RoomEvent>.broadcast();
  final _roomChanges = StreamController<Map<String, RoomInfo>>.broadcast();
  Map<String, RoomInfo> _rooms = const {};
  late final StreamSubscription<TransportUpdate> _subscription;
  late TransportStatus _status;
  bool _disposed = false;
  Future<void>? _disposal;

  Map<String, RoomInfo> get rooms => _rooms;
  Stream<ServerEvent> get globalEvents => _globalEvents.stream;
  Stream<RoomEvent> get roomEvents => _roomEvents.stream;
  Stream<Map<String, RoomInfo>> get roomChanges => _roomChanges.stream;

  /// A filter over the shared stream; it does not allocate a controller per room.
  Stream<RoomEvent> eventsForRoom(String roomId) =>
      roomEvents.where((event) => event.roomId == roomId);

  void _receive(String message) {
    if (_disposed) return;
    for (final record in parseServerMessage(message)) {
      final event = decodeServerRecord(record);
      if (event == null) continue;
      final lifecycle =
          event is RoomInitEvent ||
          event is RoomTitleEvent ||
          event is RoomDeinitEvent;
      // Showdown permits omission of the header for lobby messages.
      final roomId = event.roomId ?? (lifecycle ? 'lobby' : null);
      if (roomId == null) {
        _globalEvents.add(event);
      } else {
        _apply(roomId, event);
        _roomEvents.add(RoomEvent(roomId: roomId, event: event));
      }
    }
  }

  void _apply(String id, ServerEvent event) {
    final previous = _rooms[id];
    if (event is RoomInitEvent) {
      // A new init starts a new snapshot: do not carry a title from an old session.
      _publish({
        ..._rooms,
        id: RoomInfo(
          id: id,
          type: event.roomType,
          isStale:
              _status != TransportStatus.connected &&
              _status != TransportStatus.connecting,
        ),
      });
    } else if (event is RoomTitleEvent && previous != null) {
      _publish({
        ..._rooms,
        id: RoomInfo(
          id: id,
          type: previous.type,
          title: event.title,
          isStale: previous.isStale,
        ),
      });
    } else if (event is RoomDeinitEvent && previous != null) {
      _publish({..._rooms}..remove(id));
    }
  }

  void _markStale() {
    if (_disposed || !_rooms.values.any((room) => !room.isStale)) return;
    _publish({
      for (final room in _rooms.values)
        room.id: RoomInfo(
          id: room.id,
          type: room.type,
          title: room.title,
          isStale: true,
        ),
    });
  }

  void _publish(Map<String, RoomInfo> rooms) {
    _rooms = Map.unmodifiable(rooms);
    _roomChanges.add(_rooms);
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _markStale();
    _disposed = true;
    await _subscription.cancel();
    await Future.wait([
      _globalEvents.close(),
      _roomEvents.close(),
      _roomChanges.close(),
    ]);
  }
}
