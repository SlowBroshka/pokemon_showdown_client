import 'dart:async';

import '../../protocol/client_commands.dart';
import '../../protocol/server_event_decoder.dart';
import '../../session/showdown_session.dart';
import '../state/battle_reducer.dart';
import 'battle_choice.dart';
import 'battle_decision_phase.dart';
import 'captured_battle_choice.dart';

export 'battle_choice.dart';
export 'battle_decision_phase.dart';
export 'captured_battle_choice.dart';

/// One room in one connection epoch. Create before joining the room; no replay.
/// Owns subscriptions only, never the shared session or its connection.
final class BattleDecisionController {
  BattleDecisionController({
    required ShowdownSession session,
    required String roomId,
    this.responseTimeout = const Duration(seconds: 30),
  }) : _session = session,
       _state = BattleState(
         roomId: roomId,
         connectionEpoch: session.connectionEpoch,
       ) {
    // Reuse command validation without sending anything.
    ChooseCommand(roomId: roomId, choice: const BattleChoice.move(1));
    if (!session.isCurrent(session.connectionEpoch) ||
        responseTimeout <= Duration.zero) {
      throw ArgumentError(
        'An active session and positive timeout are required',
      );
    }
    _subscription = session.updates.listen(_receive, onDone: _invalidate);
  }

  final ShowdownSession _session;
  final Object _contextToken = Object();
  final Duration responseTimeout;
  late final StreamSubscription<SessionUpdate> _subscription;
  final _changes = StreamController<void>.broadcast();
  BattleState _state;
  BattleDecisionPhase _phase = BattleDecisionPhase.ready;
  Timer? _settleTimer;
  Timer? _responseTimer;
  int _seenSequence = -1;
  int _settledSequence = -1;
  bool _disposed = false;
  bool _choicesStopped = false;
  bool _outstanding = false;
  // Errors have no request identifier. Once an unresolved send is superseded,
  // later errors cannot safely authorize a retry, even for a newer submission.
  bool _ambiguousErrors = false;

  BattleState get state => _state;
  BattleDecisionPhase get phase => _phase;
  Stream<void> get changes => _changes.stream;

  bool get canChoose =>
      !_disposed &&
      !_choicesStopped &&
      _phase == BattleDecisionPhase.ready &&
      !_state.stale &&
      _state.phase == BattlePhase.started &&
      _state.compatible &&
      _session.isCurrent(_state.connectionEpoch) &&
      _session.status == TransportStatus.connected &&
      _settledSequence >= 0 &&
      _settledSequence == _seenSequence &&
      _seenSequence == _session.latestUpdateSequence &&
      (_state.request?.moveSlots.isNotEmpty == true ||
          _state.request?.switchSlots.isNotEmpty == true);

  bool _legal(BattleChoice choice) {
    final request = _state.request;
    if (request == null) return false;
    return choice.isMove
        ? request.moveSlots.contains(choice.slot) &&
              (!choice.terastallize || request.canTerastallize)
        : request.switchSlots.contains(choice.slot);
  }

  CapturedBattleChoice? capture(BattleChoice choice) {
    if (!canChoose || !_legal(choice)) return null;
    return CapturedBattleChoice(
      roomId: _state.roomId,
      connectionEpoch: _state.connectionEpoch,
      requestRevision: _state.requestRevision,
      rqid: _state.request!.rqid,
      choice: choice,
      contextToken: _contextToken,
    );
  }

  /// True means a socket write only, never server acceptance. False never
  /// grants retry permission: inspect phase/canChoose after a send failure.
  bool submit(CapturedBattleChoice captured) {
    if (!canChoose ||
        !identical(captured.contextToken, _contextToken) ||
        captured.roomId != _state.roomId ||
        captured.connectionEpoch != _state.connectionEpoch ||
        captured.requestRevision != _state.requestRevision ||
        captured.rqid != _state.request!.rqid ||
        !_legal(captured.choice)) {
      return false;
    }
    final command = ChooseCommand(
      roomId: captured.roomId,
      choice: captured.choice,
      rqid: captured.rqid,
    );
    _phase = BattleDecisionPhase.submitted;
    _outstanding = true;
    try {
      _session.send(command, connectionEpoch: captured.connectionEpoch);
    } on Object {
      // A transport failure cannot prove the server did not receive the write.
      _phase = BattleDecisionPhase.uncertain;
      _notify();
      return false;
    }
    _responseTimer = Timer(responseTimeout, () {
      _phase = BattleDecisionPhase.uncertain;
      _notify();
    });
    _notify();
    return true;
  }

  void _receive(SessionUpdate update) {
    if (_disposed) return;
    if (update.connectionEpoch != _state.connectionEpoch ||
        !_session.isCurrent(_state.connectionEpoch)) {
      _invalidate();
      return;
    }
    _seenSequence = update.sequence;
    _settledSequence = -1;
    _settleTimer?.cancel();
    // All records in a transport frame share a sequence. An event-loop barrier
    // lets their asynchronous broadcast deliveries drain before enabling sends.
    _settleTimer = Timer(Duration.zero, () {
      _settledSequence = _seenSequence;
      _notify();
    });
    if (update.status != null &&
        update.status != TransportStatus.connected &&
        update.status != TransportStatus.connecting) {
      _invalidate();
      return;
    }
    final event = update.event;
    if (event != null && update.roomId == _state.roomId) {
      final previousRevision = _state.requestRevision;
      _state = reduceBattleEvent(
        _state,
        event,
        connectionEpoch: update.connectionEpoch,
      );
      if (_state.requestRevision != previousRevision) {
        _ambiguousErrors |= _outstanding;
        _outstanding = false;
        _responseTimer?.cancel();
        _phase = BattleDecisionPhase.ready;
      }
      if (_choicesStopped || _state.terminal || _state.unsupported) {
        _responseTimer?.cancel();
        _phase = BattleDecisionPhase.inactive;
      } else if (event is ServerErrorEvent && _outstanding) {
        final invalid = event.message.startsWith('[Invalid choice]');
        final unavailable = event.message.startsWith('[Unavailable choice]');
        if (invalid || unavailable) {
          _responseTimer?.cancel();
          _phase = invalid && !_ambiguousErrors
              ? BattleDecisionPhase.ready
              : BattleDecisionPhase.awaitingRequest;
          _outstanding = false;
        }
      }
    }
    _notify();
  }

  void _invalidate() {
    if (_disposed) return;
    _settleTimer?.cancel();
    _responseTimer?.cancel();
    _state = _state.markStale();
    _phase = BattleDecisionPhase.inactive;
    _notify();
  }

  /// Permanently revoke send permission before /leave or owner cleanup.
  /// Keep consuming events so a final result/deinit is still projected.
  void stopChoosing() {
    if (_disposed || _choicesStopped) return;
    _choicesStopped = true;
    _responseTimer?.cancel();
    _phase = BattleDecisionPhase.inactive;
    _notify();
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    _responseTimer?.cancel();
    // Initiate both operations synchronously; cancelled upstream deliveries are
    // already guarded by _disposed, so stream closure need not wait for cancel.
    await Future.wait([_subscription.cancel(), _changes.close()]);
  }
}
