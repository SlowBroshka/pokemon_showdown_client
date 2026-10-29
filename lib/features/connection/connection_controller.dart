import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/battle/decisions/battle_decision_controller.dart';
import '../../core/session/showdown_session.dart';
import '../../core/transport/showdown_endpoint.dart';
import '../rooms/room_owner.dart';
import 'connection_message.dart';

/// Connection facade for the existing screen; RoomOwner exclusively owns rooms.
final class ConnectionController extends ChangeNotifier {
  ConnectionController({
    ShowdownSession? session,
    this.roomTimeout = const Duration(seconds: 10),
  }) : _ownsSession = session == null,
       _session = session ?? ShowdownSession() {
    rooms = RoomOwner(_session, roomTimeout: roomTimeout);
    rooms.addListener(_changed);
  }

  static const defaultEndpoint = 'wss://sim3.psim.us/showdown/websocket';
  final bool _ownsSession;
  final ShowdownSession _session;
  final Duration roomTimeout;
  late final RoomOwner rooms;
  bool _disposed = false;
  Future<void>? _cleanup;

  TransportStatus get status => _session.status;
  RoomInfo? get room => rooms.room;
  BattleDecisionController? get battle => rooms.battle;
  String? get joiningId => rooms.joiningId;
  bool get leaving => rooms.leaving;
  bool get disconnecting => rooms.disconnecting;
  ConnectionMessage? get error => rooms.error;
  List<ConnectionMessage> get notices => rooms.notices;
  bool get canConnect =>
      !_disposed && !disconnecting && status == TransportStatus.disconnected;
  bool get canJoin => !_disposed && rooms.canJoin;
  bool get canLeave => !_disposed && rooms.canLeave;

  Future<void> connect(String address) async {
    if (!canConnect) return;
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !isAllowedShowdownEndpoint(uri)) {
      rooms.report(ConnectionMessage.invalidWssAddress);
      return;
    }
    rooms.resetForConnection();
    try {
      final pending = _session.connect(uri);
      _changed();
      await pending;
    } on TransportException {
      // Shared session failures are reported by the owner.
    } on ArgumentError {
      rooms.report(ConnectionMessage.invalidAddress);
    } on StateError {
      rooms.report(ConnectionMessage.connectionUnavailable);
    }
    _changed();
  }

  Future<void> disconnect() async {
    if (!_disposed) await rooms.disconnect();
  }

  void join(String id) {
    if (!_disposed) rooms.join(id);
  }

  void leave() {
    if (!_disposed) rooms.leave();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> get closed => _cleanup ?? Future.value();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    rooms.removeListener(_changed);
    rooms.dispose();
    _cleanup = _close();
    super.dispose();
  }

  Future<void> _close() async {
    await rooms.closed;
    if (_ownsSession) await _session.dispose();
  }
}
