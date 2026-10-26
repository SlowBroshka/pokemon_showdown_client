import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/battle/decisions/battle_decision_controller.dart';
import '../../core/protocol/client_commands.dart';
import '../../core/protocol/server_event_decoder.dart';
import '../../core/session/showdown_session.dart';
import 'connection_message.dart';

/// Owns one selected room, its battle context and pending room operation.
/// An injected session remains caller-owned.
final class ConnectionController extends ChangeNotifier {
  ConnectionController({
    ShowdownSession? session,
    this.roomTimeout = const Duration(seconds: 10),
  }) : _ownsSession = session == null,
       _session = session ?? ShowdownSession() {
    if (roomTimeout <= Duration.zero) {
      throw ArgumentError('Timeout must be positive');
    }
    _subscriptions.addAll([
      _session.statuses.listen(_onStatus),
      _session.failures.listen(
        (failure) => _report(switch (failure.failure) {
          TransportFailure.timeout => ConnectionMessage.connectionTimeout,
          TransportFailure.closed => ConnectionMessage.serverClosed,
          TransportFailure.unsupportedMessage =>
            ConnectionMessage.unsupportedMessage,
          TransportFailure.send => ConnectionMessage.sendFailed,
          _ => ConnectionMessage.connectionFailed,
        }),
      ),
      _session.roomEvents.listen(_onRoom),
      _session.globalEvents.listen((update) => _onGlobal(update.event!)),
    ]);
  }

  static const defaultEndpoint = 'wss://sim3.psim.us/showdown/websocket';
  final ShowdownSession _session;
  final bool _ownsSession;
  final Duration roomTimeout;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _notices = <ConnectionMessage>[];
  RoomInfo? _room;
  String? _joiningId;
  bool _leaving = false;
  bool _disconnecting = false;
  bool _disposed = false;
  Timer? _timer;
  ConnectionMessage? _error;
  Future<void>? _cleanup;
  BattleDecisionController? _battle;
  bool _battleConfirmed = false;
  StreamSubscription<void>? _battleSubscription;
  final _pendingBattleCleanup = <Future<void>>{};

  TransportStatus get status => _session.status;
  RoomInfo? get room => _room;

  /// Selected battle, retained for its result after deinit or as stale on loss.
  /// A pending join is not exposed until the server confirms type=battle.
  BattleDecisionController? get battle => _battleConfirmed ? _battle : null;
  String? get joiningId => _joiningId;
  bool get leaving => _leaving;
  bool get disconnecting => _disconnecting;
  ConnectionMessage? get error => _error;
  List<ConnectionMessage> get notices => List.unmodifiable(_notices);
  bool get canConnect =>
      !_disposed && !_disconnecting && status == TransportStatus.disconnected;
  bool get canJoin =>
      !_disposed &&
      !_disconnecting &&
      status == TransportStatus.connected &&
      _session.isCurrent(_session.connectionEpoch) &&
      _room == null &&
      _joiningId == null &&
      !_leaving;
  bool get canLeave =>
      !_disposed &&
      !_disconnecting &&
      status == TransportStatus.connected &&
      _session.isCurrent(_session.connectionEpoch) &&
      _room != null &&
      !_room!.isStale &&
      !_leaving;

  Future<void> connect(String address) async {
    if (!canConnect) return;
    _error = null;
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      _report(ConnectionMessage.invalidWssAddress);
      return;
    }
    _room = null;
    _releaseBattle();
    try {
      final pending = _session.connect(uri);
      _changed();
      await pending;
    } on TransportException {
      // The failures stream reports network failures; cancellation is intentional.
    } on ArgumentError {
      _report(ConnectionMessage.invalidAddress);
    } on StateError {
      _report(ConnectionMessage.connectionUnavailable);
    }
    _changed();
  }

  Future<void> disconnect() async {
    if (_disposed || _disconnecting) return;
    _disconnecting = true;
    _battle?.stopChoosing();
    _clearOperation();
    _stale();
    final pending = _session.disconnect();
    _changed();
    await pending;
    _disconnecting = false;
    _changed();
  }

  void join(String id) {
    if (!canJoin) return;
    final JoinRoomCommand command;
    try {
      command = JoinRoomCommand(roomId: id.trim());
    } on ArgumentError {
      _report(ConnectionMessage.invalidRoomId);
      return;
    }
    _error = null;
    _releaseBattle();
    // Subscribe before sending: init and request may share the first frame.
    final battle = BattleDecisionController(
      session: _session,
      roomId: command.roomId,
    );
    _battle = battle;
    _battleSubscription = battle.changes.listen((_) {
      if (identical(_battle, battle) && _battleConfirmed) _changed();
    });
    _joiningId = command.roomId;
    _awaitRoom();
    _send(command);
    _changed();
  }

  void leave() {
    if (!canLeave) return;
    _error = null;
    _leaving = true;
    _battle?.stopChoosing();
    _awaitRoom();
    _send(LeaveRoomCommand(roomId: _room!.id));
    _changed();
  }

  void _awaitRoom() {
    _timer?.cancel();
    _timer = Timer(roomTimeout, () {
      _report(ConnectionMessage.roomTimeout);
      // A late init must not create a second room after a timed-out join.
      unawaited(disconnect());
    });
  }

  void _send(ClientCommand command) {
    try {
      _session.send(command, connectionEpoch: _session.connectionEpoch);
    } on TransportException {
      _clearOperation();
    } on StateError {
      _clearOperation();
      _report(ConnectionMessage.notConnected);
    }
  }

  void _onStatus(TransportStatus value) {
    if (_disposed) return;
    if (value == TransportStatus.disconnected ||
        value == TransportStatus.disposed) {
      _battle?.stopChoosing();
      if (!_battleConfirmed) _releaseBattle();
      _clearOperation();
      _stale();
    }
    _notice(switch (value) {
      TransportStatus.connecting => ConnectionMessage.connecting,
      TransportStatus.connected => ConnectionMessage.connected,
      _ => ConnectionMessage.disconnected,
    });
  }

  void _onRoom(SessionUpdate routed) {
    if (_disposed || status != TransportStatus.connected || _disconnecting) {
      return;
    }
    final event = routed.event!;
    final id = routed.roomId!;
    if (event is RoomInitEvent) {
      if (_joiningId == id || _room?.id == id) {
        if (_joiningId == id) {
          _battleConfirmed = event.roomType == 'battle';
          if (!_battleConfirmed) _releaseBattle();
        } else if (_room!.type != event.roomType) {
          // A repeated init cannot silently change the selected room's type.
          unawaited(disconnect());
          return;
        }
        _room = RoomInfo(id: id, type: event.roomType);
        if (_joiningId == id) _clearOperation();
        _notice(ConnectionMessage.roomJoined);
      } else {
        // The same owner arbitrates chat and battle joins. Never replace the
        // selected context with an unsolicited room (including another battle).
        try {
          _send(LeaveRoomCommand(roomId: id));
        } on ArgumentError {
          unawaited(disconnect());
        }
      }
    } else if (event is RoomTitleEvent && _room?.id == id) {
      _room = RoomInfo(id: id, type: _room!.type, title: event.title);
      _changed();
    } else if (event is RoomDeinitEvent &&
        (_room?.id == id || _joiningId == id)) {
      _battle?.stopChoosing();
      _room = null;
      if (!_battleConfirmed) _releaseBattle();
      _clearOperation();
      _notice(ConnectionMessage.roomLeft);
    } else if (id == _joiningId || id == _room?.id) {
      _onGlobal(event);
    }
  }

  void _onGlobal(ServerEvent event) {
    if (_disposed || _disconnecting || status != TransportStatus.connected) {
      return;
    }
    if (event is ServerErrorEvent ||
        event is PopupEvent ||
        event is NameTakenEvent ||
        (event is UnknownServerEvent && event.eventType == 'noinit')) {
      _report(ConnectionMessage.serverNotice);
      if (_joiningId != null || _leaving) unawaited(disconnect());
    }
  }

  void _stale() {
    final previous = _room;
    if (previous != null) {
      _room = RoomInfo(
        id: previous.id,
        type: previous.type,
        title: previous.title,
        isStale: true,
      );
    }
  }

  void _clearOperation() {
    _timer?.cancel();
    _timer = null;
    _joiningId = null;
    _leaving = false;
  }

  void _report(ConnectionMessage message) {
    if (_disposed) return;
    _error = message;
    _notice(message);
  }

  void _notice(ConnectionMessage message) {
    if (_disposed) return;
    _notices.insert(0, message);
    if (_notices.length > 50) _notices.removeLast();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _releaseBattle() {
    final battle = _battle;
    final subscription = _battleSubscription;
    _battle = null;
    _battleConfirmed = false;
    _battleSubscription = null;
    // dispose disables writes synchronously, before asynchronous cleanup.
    if (battle == null && subscription == null) return;
    final cleanup = Future.wait<void>([
      if (subscription != null) subscription.cancel(),
      if (battle != null) battle.dispose(),
    ]).then((_) {});
    _pendingBattleCleanup.add(cleanup);
    unawaited(
      cleanup.whenComplete(() => _pendingBattleCleanup.remove(cleanup)),
    );
  }

  /// Completion of resource cleanup after dispose(), useful for the app owner/tests.
  Future<void> get closed => _cleanup ?? Future.value();
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseBattle();
    _clearOperation();
    _cleanup = _closeResources();
    super.dispose();
  }

  Future<void> _closeResources() async {
    await Future.wait(_pendingBattleCleanup);
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    if (_ownsSession) await _session.dispose();
  }
}
