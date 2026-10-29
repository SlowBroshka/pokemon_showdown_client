import 'dart:async';

import '../../core/auth/auth_controller.dart';
import '../../core/matchmaking/formats/format_availability.dart';
import '../../core/matchmaking/formats/format_catalog_controller.dart';
import '../../core/protocol/client_commands.dart';
import '../../core/protocol/server_event_decoder.dart';
import '../../core/session/showdown_session.dart';
import '../rooms/room_handoff_phase.dart';
import '../rooms/room_owner.dart';
import 'matchmaking_state.dart';

export 'matchmaking_state.dart';

/// A captured start action, valid only for this controller and source revision.
final class MatchmakingStart {
  MatchmakingStart._(this._owner, this._epoch, this._sequence, this._identity);
  final MatchmakingController _owner;
  final int _epoch;
  final int _sequence;
  final AuthState _identity;
}

/// Compose once with the shared auth, catalog and room owner before connecting.
/// Does not own these dependencies, open sockets, authenticate or retry searches.
final class MatchmakingController {
  MatchmakingController({
    required this.session,
    required this.auth,
    required this.catalog,
    required this.rooms,
    bool experimentalEnabled = false,
    this.responseTimeout = const Duration(seconds: 10),
  }) {
    _experimentalEnabled = experimentalEnabled;
    if (!identical(auth.session, session) ||
        !identical(catalog.session, session) ||
        !identical(rooms.session, session) ||
        responseTimeout <= Duration.zero) {
      throw ArgumentError('Expected shared session and positive timeout');
    }
    _subscriptions.addAll([
      session.updates.listen(_receive, onDone: _disconnected),
      auth.changes.listen((_) => _refresh()),
      catalog.changes.listen((_) => _refresh()),
    ]);
    rooms.addListener(_refresh);
  }

  static const formatId = 'gen9randombattle';
  final ShowdownSession session;
  final AuthController auth;
  final FormatCatalogController catalog;
  final RoomOwner rooms;
  final Duration responseTimeout;
  final _changes = StreamController<MatchmakingState>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  MatchmakingState _state = const MatchmakingState(
    MatchmakingPhase.disconnected,
  );
  _Attempt? _attempt;
  AuthState? _baselineIdentity;
  int _epoch = 0;
  int _seen = -1;
  bool _settled = false;
  bool _starting = false;
  bool _disposed = false;
  late bool _experimentalEnabled;
  Timer? _deliveryTimer;
  Timer? _responseTimer;
  Future<void>? _disposal;

  MatchmakingState get state => _state;
  Stream<MatchmakingState> get changes => _changes.stream;
  bool get experimentalEnabled => _experimentalEnabled;
  set experimentalEnabled(bool value) {
    if (_disposed || value == _experimentalEnabled) return;
    _experimentalEnabled = value;
    _refresh();
  }

  bool get _fresh =>
      !_disposed &&
      session.status == TransportStatus.connected &&
      session.isCurrent(_epoch) &&
      _seen == session.latestUpdateSequence &&
      _settled;

  bool get _authorized =>
      auth.state.phase == AuthPhase.authenticated && auth.state.userId != null;

  bool get _formatAvailable =>
      catalog.availability(
        formatId,
        experimentalEnabled: _experimentalEnabled,
      ) ==
      FormatAvailability.experimental;

  bool get canStart {
    final baseline = rooms.searchBaseline;
    return !_starting &&
        _attempt == null &&
        _fresh &&
        _authorized &&
        identical(_baselineIdentity, auth.state) &&
        _formatAvailable &&
        rooms.canJoin &&
        baseline != null &&
        baseline.searching.isEmpty &&
        (baseline.games?.isEmpty ?? true);
  }

  MatchmakingStart? captureStart() =>
      canStart ? MatchmakingStart._(this, _epoch, _seen, auth.state) : null;

  /// True means local acceptance, not a server ACK. False may include an
  /// ambiguous send failure: consult state and never retry automatically.
  bool start(MatchmakingStart action) {
    if (!identical(action._owner, this) ||
        !canStart ||
        action._epoch != _epoch ||
        action._sequence != _seen ||
        !identical(action._identity, auth.state)) {
      return false;
    }
    _starting = true;
    final reservation = rooms.reserveSearch(
      userId: auth.state.userId!,
      connectionEpoch: _epoch,
      baseline: rooms.searchBaseline!,
    );
    if (reservation == null) {
      _starting = false;
      _refresh();
      return false;
    }
    final attempt = _Attempt(_epoch, auth.state, reservation);
    _attempt = attempt;
    _set(MatchmakingPhase.submitting);
    try {
      // Recheck after reservation notifications, and again between the sends.
      if (!_readyToSend(attempt)) {
        _unknown(MatchmakingNotice.conflict);
        return false;
      }
      session.send(
        const PrepareRandomTeamCommand(),
        connectionEpoch: attempt.epoch,
      );
      if (!_readyToSend(attempt)) {
        _unknown(MatchmakingNotice.conflict);
        return false;
      }
      attempt.searchIssued = true;
      session.send(
        SearchBattleCommand(formatId: formatId),
        connectionEpoch: attempt.epoch,
      );
      _armTimeout(attempt);
      return true;
    } catch (_) {
      _unknown(MatchmakingNotice.sendFailed);
      return false;
    } finally {
      _starting = false;
      _refresh();
    }
  }

  bool _sameIdentity(_Attempt attempt) =>
      attempt.epoch == session.connectionEpoch &&
      _authorized &&
      identical(attempt.identity, auth.state);

  bool _readyToSend(_Attempt attempt) =>
      _fresh &&
      _sameIdentity(attempt) &&
      _formatAvailable &&
      rooms.ownsSearch(attempt.reservation) &&
      rooms.handoffPhase == RoomHandoffPhase.reserved;

  bool get canCancel =>
      !_starting &&
      _fresh &&
      _attempt != null &&
      _attempt!.searchIssued &&
      !_attempt!.cancelRequested &&
      _sameIdentity(_attempt!) &&
      rooms.ownsSearch(_attempt!.reservation) &&
      rooms.handoffPhase == RoomHandoffPhase.reserved &&
      const [
        MatchmakingPhase.submitting,
        MatchmakingPhase.searching,
        MatchmakingPhase.stoppedObserved,
      ].contains(_state.phase);

  /// Capture state.attemptToken with the UI action; old attempts cannot cancel.
  bool cancel(Object token) {
    final attempt = _attempt;
    if (attempt == null || !identical(token, attempt.token) || !canCancel) {
      return false;
    }
    attempt.cancelRequested = true;
    attempt.earlyCancel = !attempt.queueSeen;
    _set(MatchmakingPhase.cancelling);
    _responseTimer?.cancel();
    _responseTimer = null;
    _armTimeout(attempt);
    return _sendCancel(attempt);
  }

  bool _sendCancel(_Attempt attempt) {
    if (!_fresh ||
        !_sameIdentity(attempt) ||
        !rooms.ownsSearch(attempt.reservation) ||
        rooms.handoffPhase != RoomHandoffPhase.reserved) {
      return false;
    }
    try {
      session.send(
        CancelSearchCommand(formatId: formatId),
        connectionEpoch: attempt.epoch,
      );
      return true;
    } catch (_) {
      _unknown(MatchmakingNotice.sendFailed);
      return false;
    }
  }

  void _receive(SessionUpdate update) {
    if (_disposed || update.connectionEpoch != session.connectionEpoch) return;
    _seen = update.sequence;
    _settled = false;
    _deliveryTimer?.cancel();
    _deliveryTimer = Timer(Duration.zero, () {
      if (_disposed) return;
      _settled = true;
      _refresh();
      final attempt = _attempt;
      if (attempt != null &&
          attempt.lateCancelPending &&
          _fresh &&
          _state.phase == MatchmakingPhase.cancelling) {
        attempt.lateCancelPending = false;
        _sendCancel(attempt);
      }
    });
    if (update.status != null) {
      if (update.status == TransportStatus.connecting) {
        _reset();
        _epoch = update.connectionEpoch;
        _set(MatchmakingPhase.unavailable);
      } else if (update.status == TransportStatus.connected) {
        _epoch = update.connectionEpoch;
        _refresh();
      } else {
        _disconnected();
      }
      return;
    }
    if (!session.isCurrent(update.connectionEpoch)) return;
    if (update.roomId == null && update.event is UpdateSearchEvent) {
      final snapshot = (update.event as UpdateSearchEvent).result.snapshot;
      _baselineIdentity = snapshot != null && _authorized ? auth.state : null;
    }
    final attempt = _attempt;
    if (attempt == null) {
      _refresh();
      return;
    }
    if (!_sameIdentity(attempt) || !rooms.ownsSearch(attempt.reservation)) {
      _unknown(MatchmakingNotice.conflict);
      return;
    }
    if (update.roomId == null) {
      final event = update.event;
      if (event is PopupEvent || event is ServerErrorEvent) {
        _set(_state.phase, notice: MatchmakingNotice.serverNotice);
      } else if (event is UpdateSearchEvent) {
        final snapshot = event.result.snapshot;
        if (snapshot == null) {
          _unknown(MatchmakingNotice.invalidSearchSnapshot);
        } else if (_state.phase != MatchmakingPhase.outcomeUnknown &&
            _state.phase != MatchmakingPhase.inBattle) {
          if (snapshot.searching.any((id) => id != formatId)) {
            _unknown(MatchmakingNotice.conflict);
          } else if (snapshot.searching.contains(formatId)) {
            final first = !attempt.queueSeen;
            attempt.queueSeen = true;
            if (attempt.cancelRequested) {
              if (first && attempt.earlyCancel) {
                attempt.lateCancelPending = true;
              }
              _set(MatchmakingPhase.cancelling);
            } else {
              _responseTimer?.cancel();
              _responseTimer = null;
              _set(MatchmakingPhase.searching);
            }
          } else {
            _set(MatchmakingPhase.stoppedObserved);
            _armTimeout(attempt);
          }
        }
      }
    }
    _refresh();
  }

  void _refresh() {
    if (_disposed || _starting) return;
    if (!session.isCurrent(_epoch)) {
      _disconnected();
      return;
    }
    final attempt = _attempt;
    if (attempt == null) {
      _set(canStart ? MatchmakingPhase.idle : MatchmakingPhase.unavailable);
      // Availability reasons and the opt-in may change without a phase change.
      _changes.add(_state);
      return;
    }
    if (!_sameIdentity(attempt) || !rooms.ownsSearch(attempt.reservation)) {
      _unknown(MatchmakingNotice.conflict);
      return;
    }
    switch (rooms.handoffPhase) {
      case RoomHandoffPhase.adopted:
        _responseTimer?.cancel();
        _responseTimer = null;
        _set(MatchmakingPhase.inBattle);
      case RoomHandoffPhase.awaitingEvidence:
        _responseTimer?.cancel();
        _responseTimer = null;
        _set(MatchmakingPhase.awaitingBattle);
      case RoomHandoffPhase.outcomeUnknown:
      case RoomHandoffPhase.idle:
        _unknown(
          _state.phase == MatchmakingPhase.outcomeUnknown
              ? _state.notice ?? MatchmakingNotice.conflict
              : MatchmakingNotice.conflict,
        );
      case RoomHandoffPhase.reserved:
        // An empty snapshot, timeout or cancelled UI action never releases it.
        break;
    }
    // canCancel may change after the source frame settles without a phase change.
    _changes.add(_state);
  }

  void _armTimeout(_Attempt attempt) {
    if (_responseTimer != null) return;
    _responseTimer = Timer(responseTimeout, () {
      _responseTimer = null;
      if (!_disposed &&
          identical(_attempt, attempt) &&
          session.isCurrent(attempt.epoch)) {
        _unknown(MatchmakingNotice.timeout);
      }
    });
  }

  void _unknown(MatchmakingNotice notice) {
    _responseTimer?.cancel();
    _responseTimer = null;
    _attempt?.lateCancelPending = false;
    _set(MatchmakingPhase.outcomeUnknown, notice: notice);
  }

  void _set(MatchmakingPhase phase, {MatchmakingNotice? notice}) {
    if (_disposed) return;
    final nextNotice = notice ?? _state.notice;
    if (_state.phase == phase &&
        identical(_state.attemptToken, _attempt?.token) &&
        _state.notice == nextNotice) {
      return;
    }
    _state = MatchmakingState(
      phase,
      attemptToken: _attempt?.token,
      notice: nextNotice,
    );
    _changes.add(_state);
  }

  void _reset() {
    _responseTimer?.cancel();
    _responseTimer = null;
    _attempt = null;
    _baselineIdentity = null;
    _state = const MatchmakingState(MatchmakingPhase.disconnected);
  }

  void _disconnected() {
    if (_disposed) return;
    final notice = _state.notice;
    _reset();
    _epoch = 0;
    _set(MatchmakingPhase.disconnected, notice: notice);
    _changes.add(_state);
  }

  Future<void> dispose() {
    if (_disposed) return _disposal!;
    _disposed = true;
    _deliveryTimer?.cancel();
    _responseTimer?.cancel();
    rooms.removeListener(_refresh);
    // Leave uncertain reservations with the owner; dispose is not a server ACK.
    _attempt = null;
    return _disposal = _close();
  }

  Future<void> _close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }
}

final class _Attempt {
  _Attempt(this.epoch, this.identity, this.reservation);
  final Object token = Object();
  final int epoch;
  final AuthState identity;
  final Object reservation;
  bool searchIssued = false;
  bool queueSeen = false;
  bool cancelRequested = false;
  bool earlyCancel = false;
  bool lateCancelPending = false;
}
