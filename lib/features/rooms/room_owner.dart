import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/battle/decisions/battle_decision_controller.dart';
import '../../core/protocol/client_commands.dart';
import '../../core/protocol/server_event_decoder.dart';
import '../../core/session/showdown_session.dart';

import 'dart:convert';

import '../../core/auth/auth_user_id.dart';
import '../../core/matchmaking/search/search_snapshot.dart';
import 'room_handoff_phase.dart';
import '../connection/connection_message.dart';

/// Owns one selected room, its battle context and pending room operation.
/// An injected session remains caller-owned.
final class RoomOwner extends ChangeNotifier {
  RoomOwner(
    this._session, {
    this.roomTimeout = const Duration(seconds: 10),
    this.handoffTimeout = const Duration(seconds: 10),
  }) {
    if (roomTimeout <= Duration.zero || handoffTimeout <= Duration.zero) {
      throw ArgumentError('Timeout must be positive');
    }
    _subscriptions.addAll([
      _session.updates.listen(_receive, onDone: _sessionEnded),
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
    ]);
  }

  final ShowdownSession _session;

  /// Shared session identity for composition checks; ownership stays unchanged.
  ShowdownSession get session => _session;
  final Duration roomTimeout;
  final Duration handoffTimeout;
  final _battleUpdates = StreamController<SessionUpdate>.broadcast(sync: true);
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
  SearchSnapshot? _baseline;
  SearchSnapshot? get searchBaseline => _baseline;
  String? _currentIdentity;
  int _seenSequence = -1;
  bool _settled = false;
  Timer? _deliveryTimer;
  Object? _reservation;
  int _reservationEpoch = 0;
  String? _identity;
  String? _candidate;
  bool _listed = false;
  bool _initialized = false;
  final _players = <String, String>{};
  String? _requestSide;
  bool _requestIdentityConfirmed = false;
  String? _admittedSide;
  final _buffer = <SessionUpdate>[];
  int _bufferBytes = 0;
  Timer? _handoffTimer;
  RoomHandoffPhase _handoff = RoomHandoffPhase.idle;
  RoomHandoffPhase get handoffPhase => _handoff;
  String? get candidateRoomId => _candidate;

  /// Caller must supply the fresh account baseline and confirmed identity for
  /// this epoch. This reserves ownership only; it does not start a search.
  Object? reserveSearch({
    required String userId,
    required int connectionEpoch,
    required SearchSnapshot baseline,
  }) {
    if (!canJoin ||
        connectionEpoch != _session.connectionEpoch ||
        !identical(baseline, _baseline) ||
        userId != _currentIdentity ||
        !_settled ||
        _seenSequence != _session.latestUpdateSequence ||
        authUserId(userId) != userId ||
        baseline.searching.isNotEmpty ||
        baseline.games?.isNotEmpty == true) {
      return null;
    }
    _releaseBattle();
    _reservation = Object();
    _reservationEpoch = _session.connectionEpoch;
    _identity = userId;
    _handoff = RoomHandoffPhase.reserved;
    _changed();
    return _reservation;
  }

  /// Whether a caller still owns this reservation in the active connection.
  bool ownsSearch(Object token) =>
      !_disposed &&
      identical(token, _reservation) &&
      _session.isCurrent(_reservationEpoch);

  /// Only for an unsent/definitively resolved search. Cancellation of a server
  /// search is NOT such proof. Stale tokens and candidates cannot release it.
  bool releaseSearch(Object token) {
    if (!identical(token, _reservation) ||
        _handoff != RoomHandoffPhase.reserved ||
        !_session.isCurrent(_reservationEpoch)) {
      return false;
    }
    _clearHandoff();
    _changed();
    return true;
  }

  void _clearHandoff() {
    _handoffTimer?.cancel();
    _handoffTimer = null;
    _reservation = null;
    _reservationEpoch = 0;
    _identity = null;
    _candidate = null;
    _listed = false;
    _initialized = false;
    _players.clear();
    _requestSide = null;
    _requestIdentityConfirmed = false;
    _admittedSide = null;
    _buffer.clear();
    _bufferBytes = 0;
    _handoff = RoomHandoffPhase.idle;
  }

  void _handoffFailed() {
    _handoffTimer?.cancel();
    _buffer.clear();
    _bufferBytes = 0;
    _battle?.stopChoosing();
    _handoff = RoomHandoffPhase.outcomeUnknown;
    _report(ConnectionMessage.serverNotice);
  }

  void _sessionEnded() {
    if (_disposed) return;
    _clearHandoff();
    _battle?.stopChoosing();
    _stale();
    _changed();
  }

  void _receive(SessionUpdate update) {
    if (_disposed || update.connectionEpoch != _session.connectionEpoch) return;
    _seenSequence = update.sequence;
    _settled = false;
    _deliveryTimer?.cancel();
    _deliveryTimer = Timer(Duration.zero, () {
      if (_disposed) return;
      _settled = true;
      _changed();
    });
    if (update.status != null) {
      if (update.status != TransportStatus.connected) {
        _baseline = null;
        _currentIdentity = null;
      }
      _onStatus(update.status!);
      _battleUpdates.add(update);
      return;
    }
    if (!_session.isCurrent(update.connectionEpoch) || _disconnecting) return;
    if (update.roomId == null && update.event is UpdateSearchEvent) {
      _baseline = (update.event as UpdateSearchEvent).result.snapshot;
    }
    if (update.roomId == null && update.event is UpdateUserEvent) {
      final user = update.event as UpdateUserEvent;
      final full = user.user;
      final name = full.isNotEmpty && !RegExp(r'^[a-zA-Z0-9]').hasMatch(full)
          ? full.substring(1)
          : full;
      _currentIdentity = user.named ? authUserId(name.split('@').first) : null;
    }
    if (_reservation != null && _handleHandoff(update)) return;
    if (update.event != null) {
      if (update.roomId == null) {
        _onGlobal(update.event!);
      } else {
        _onRoom(update);
      }
    }
    _battleUpdates.add(update);
  }

  bool _selectCandidate(String id) {
    if (!id.startsWith('battle-')) {
      _handoffFailed();
      return false;
    }
    try {
      JoinRoomCommand(roomId: id);
    } on ArgumentError {
      _handoffFailed();
      return false;
    }
    if (_candidate != null && _candidate != id) {
      _handoffFailed();
      return false;
    }
    if (_candidate == null) {
      _candidate = id;
      _handoff = RoomHandoffPhase.awaitingEvidence;
      _handoffTimer = Timer(handoffTimeout, _handoffFailed);
      _changed();
    }
    return true;
  }

  bool _handleHandoff(SessionUpdate update) {
    if (update.connectionEpoch != _reservationEpoch) return true;
    final event = update.event;
    if (event is UpdateUserEvent && update.roomId == null) {
      final full = event.user;
      final name = full.isNotEmpty && !RegExp(r'^[a-zA-Z0-9]').hasMatch(full)
          ? full.substring(1)
          : full;
      if (!event.named || authUserId(name.split('@').first) != _identity) {
        _handoffFailed();
      }
    }
    if (_handoff == RoomHandoffPhase.outcomeUnknown) {
      // Keep the already selected battle's result/history, but never admit a new room.
      return update.roomId != _room?.id || _room == null;
    }
    if (update.roomId == null && event is UpdateSearchEvent) {
      final snapshot = event.result.snapshot;
      if (snapshot == null) {
        _handoffFailed();
        return true;
      }
      final games = snapshot.games ?? const <String, String>{};
      if (games.length > 1) {
        _handoffFailed();
        return true;
      }
      if (games.isNotEmpty) {
        if (!_selectCandidate(games.keys.single)) return true;
        _listed = true;
      } else if (_handoff != RoomHandoffPhase.adopted) {
        _listed = false;
      }
      if (_handoff != RoomHandoffPhase.adopted) {
        _tryAdopt(update, buffered: false);
        return true;
      }
    }
    if (_handoff == RoomHandoffPhase.adopted) {
      if (update.roomId == _room?.id &&
          event is BattlePlayerEvent &&
          event.player.sideId == _admittedSide &&
          authUserId(event.player.name) != _identity) {
        _handoffFailed();
      }
      if (update.roomId == _room?.id &&
          event is BattleRequestEvent &&
          event.request.side != null) {
        final side = event.request.side!;
        if (side.id != _admittedSide ||
            (side.name != null && authUserId(side.name!) != _identity)) {
          _handoffFailed();
        }
      }
      if (event is RoomInitEvent && update.roomId != _room?.id) {
        _handoffFailed();
        return true;
      }
      return false;
    }
    final id = update.roomId;
    if (id == null) return false;
    if (event is RoomInitEvent) {
      if (event.roomType != 'battle' || !_selectCandidate(id)) {
        _handoffFailed();
        return true;
      }
    }
    if (id != _candidate) return true;
    if (event == null) return true;
    final bytes = utf8.encode(event.record.rawLine).length;
    if (_buffer.length >= 256 || _bufferBytes + bytes > 256 * 1024) {
      _handoffFailed();
      return true;
    }
    _buffer.add(update);
    _bufferBytes += bytes;
    if (event is RoomInitEvent) _initialized = true;
    if (event is RoomDeinitEvent || event is MalformedServerEvent) {
      _handoffFailed();
      return true;
    }
    if (event is BattlePlayerEvent) {
      _players[event.player.sideId] = event.player.name;
    }
    if (event is BattleRequestEvent && event.request.side != null) {
      final side = event.request.side!;
      _requestSide = side.id;
      _requestIdentityConfirmed =
          side.name != null && authUserId(side.name!) == _identity;
      if (side.name != null && authUserId(side.name!) != _identity) {
        _handoffFailed();
        return true;
      }
    }
    _tryAdopt(update, buffered: true);
    return true;
  }

  void _tryAdopt(SessionUpdate trigger, {required bool buffered}) {
    if (!_listed || !_initialized || _candidate == null) return;
    final sides = _players.entries
        .where((p) => authUserId(p.value) == _identity)
        .map((p) => p.key)
        .toList();
    if (_requestIdentityConfirmed && _requestSide != null) {
      final publicName = _players[_requestSide];
      if (publicName != null && authUserId(publicName) != _identity) {
        _handoffFailed();
        return;
      }
      if (sides.isEmpty) sides.add(_requestSide!);
    }
    if (sides.length > 1 ||
        (sides.length == 1 &&
            _requestSide != null &&
            sides.single != _requestSide)) {
      _handoffFailed();
      return;
    }
    if (sides.length != 1 || !const ['p1', 'p2'].contains(sides.single)) return;
    _releaseBattle();
    final controller = BattleDecisionController(
      session: _session,
      roomId: _candidate!,
      updates: _battleUpdates.stream,
    );
    _battle = controller;
    _battleConfirmed = true;
    _room = RoomInfo(id: _candidate!, type: 'battle');
    _battleSubscription = controller.changes.listen((_) {
      if (identical(_battle, controller)) _changed();
    });
    _handoffTimer?.cancel();
    _handoff = RoomHandoffPhase.adopted;
    _admittedSide = sides.single;
    for (final pending in _buffer) {
      if (pending.event is RoomTitleEvent) {
        _room = RoomInfo(
          id: _candidate!,
          type: 'battle',
          title: (pending.event as RoomTitleEvent).title,
        );
      }
      _battleUpdates.add(pending);
    }
    _buffer.clear();
    _bufferBytes = 0;
    if (!buffered) _battleUpdates.add(trigger);
    _notice(ConnectionMessage.roomJoined);
  }

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
  bool get canJoin =>
      !_disposed &&
      !_disconnecting &&
      status == TransportStatus.connected &&
      _session.isCurrent(_session.connectionEpoch) &&
      _reservation == null &&
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

  /// Called before a new connection; never reuses the old room context.
  void resetForConnection() {
    _error = null;
    _room = null;
    _releaseBattle();
    _clearHandoff();
  }

  void report(ConnectionMessage message) => _report(message);

  Future<void> disconnect() async {
    if (_disposed || _disconnecting) return;
    _disconnecting = true;
    _clearHandoff();
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
      updates: _battleUpdates.stream,
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
    _clearHandoff();
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
    if (value == TransportStatus.connecting) {
      // Previous-epoch disconnect notifications may have been dropped when a
      // new connection starts immediately. Never keep their room reservation.
      _clearHandoff();
      _clearOperation();
      _releaseBattle();
      _room = null;
    }
    if (value == TransportStatus.disconnected ||
        value == TransportStatus.disposed) {
      _clearHandoff();
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
      _clearHandoff();
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
    _deliveryTimer?.cancel();
    _releaseBattle();
    _clearHandoff();
    _clearOperation();
    _cleanup = _closeResources();
    super.dispose();
  }

  Future<void> _closeResources() async {
    await Future.wait(_pendingBattleCleanup);
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _battleUpdates.close();
  }
}
