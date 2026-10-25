import 'dart:async';

import '../protocol/client_commands.dart';
import '../protocol/server_event_decoder.dart';
import '../session/showdown_session.dart';
import 'auth_api_client.dart';
import 'auth_attempt.dart';
import 'auth_challenge.dart';
import 'auth_phase.dart';
import 'auth_state.dart';
import 'auth_user_id.dart';

export 'auth_failure.dart';
export 'auth_phase.dart';
export 'auth_state.dart';

/// Attach before connecting. Owns the auth API, subscriptions and timers, but
/// NOT the shared session. No Flutter, password retention, retries or persistence.
final class AuthController {
  AuthController({
    required this.session,
    AuthApiClient? api,
    this.challengeTimeout = const Duration(seconds: 10),
    this.confirmationTimeout = const Duration(seconds: 10),
  }) : _api = api ?? AuthApiClient() {
    if (challengeTimeout <= Duration.zero ||
        confirmationTimeout <= Duration.zero) {
      throw ArgumentError('Auth timeouts must be positive');
    }
    _subscription = session.updates.listen(_receive, onDone: _connectionLost);
    if (session.isCurrent(session.connectionEpoch)) {
      _beginEpoch(session.connectionEpoch);
    }
  }

  final ShowdownSession session;
  final AuthApiClient _api;
  final Duration challengeTimeout;
  final Duration confirmationTimeout;
  final _changes = StreamController<AuthState>.broadcast();
  late final StreamSubscription<SessionUpdate> _subscription;
  AuthState _state = const AuthState(AuthPhase.disconnected);
  AuthAttempt? _attempt;
  String? _challenge;
  int _epoch = 0;
  int _challengeRevision = 0;
  int _attemptId = 0;
  Timer? _challengeTimer;
  Timer? _confirmationTimer;
  Future<void>? _httpWork;
  Future<void>? _disconnectWork;
  Future<void>? _disposal;
  bool _disposed = false;

  AuthState get state => _state;
  Stream<AuthState> get changes => _changes.stream;
  bool get canLogin =>
      !_disposed &&
      _state.phase == AuthPhase.ready &&
      _attempt == null &&
      _httpWork == null &&
      _disconnectWork == null &&
      _challenge != null &&
      session.status == TransportStatus.connected &&
      session.isCurrent(_epoch) &&
      _supportedServer;

  bool get _supportedServer {
    final endpoint = session.endpoint;
    return endpoint != null &&
        endpoint.scheme == 'wss' &&
        endpoint.host == 'sim3.psim.us' &&
        (!endpoint.hasPort || endpoint.port == 443) &&
        endpoint.path == '/showdown/websocket' &&
        !endpoint.hasQuery &&
        !endpoint.hasFragment &&
        endpoint.userInfo.isEmpty;
  }

  /// Completes when this attempt is confirmed, rejected, cancelled or invalidated.
  /// Normal failures are in state.error, not unhandled UI futures. A duplicate
  /// invocation or invocation while unavailable is a no-op.
  Future<void> login({required String username, required String password}) {
    if (!canLogin) return Future.value();
    final attempt = AuthAttempt(++_attemptId, _epoch, _challengeRevision);
    _attempt = attempt;
    _set(AuthPhase.authenticating);
    _httpWork = _authenticate(attempt, username, password, _challenge!);
    return attempt.completed.future;
  }

  Future<void> _authenticate(
    AuthAttempt attempt,
    String name,
    String password,
    String challenge,
  ) async {
    try {
      final result = await _api.login(
        username: name,
        password: password,
        challstr: challenge,
      );
      // Drain already queued socket updates before acting on the HTTP result.
      // A new challenge may have arrived while its routed callback was queued.
      await Future<void>.delayed(Duration.zero);
      if (!_current(attempt)) {
        if (identical(_attempt, attempt)) _connectionLost();
        return;
      }
      attempt.username = result.username;
      attempt.userId = result.userId;
      // Source watermark, not delivery time: an already received but queued
      // updateuser must not be mistaken for acknowledgement of this /trn.
      attempt.sentAfterSequence = session.latestUpdateSequence;
      _set(AuthPhase.awaitingConfirmation);
      _confirmationTimer = Timer(confirmationTimeout, () {
        if (identical(_attempt, attempt)) {
          _disconnectFor(AuthFailure.confirmationTimeout);
        }
      });
      try {
        session.send(
          TrnCommand(username: result.username, assertion: result.assertion),
          connectionEpoch: attempt.epoch,
        );
      } catch (_) {
        _disconnectFor(AuthFailure.sendFailed);
      }
    } on AuthException catch (error) {
      if (_current(attempt)) {
        _invalidateAttempt();
        _set(_idlePhase, error: error.failure);
      } else if (identical(_attempt, attempt)) {
        _connectionLost();
      }
    } catch (_) {
      if (_current(attempt)) {
        _invalidateAttempt();
        _set(_idlePhase, error: AuthFailure.network);
      }
    } finally {
      _httpWork = null;
      if (!_disposed) {
        _changes.add(_state); // canLogin may have become available.
      }
    }
  }

  bool _current(AuthAttempt attempt) =>
      !_disposed &&
      identical(_attempt, attempt) &&
      attempt.epoch == _epoch &&
      attempt.challengeRevision == _challengeRevision &&
      session.isCurrent(attempt.epoch) &&
      session.status == TransportStatus.connected &&
      _supportedServer;

  AuthPhase get _idlePhase =>
      _challenge != null && session.status == TransportStatus.connected
      ? AuthPhase.ready
      : AuthPhase.waitingChallenge;

  void _receive(SessionUpdate update) {
    if (_disposed || update.connectionEpoch != session.connectionEpoch) return;
    final status = update.status;
    if (status != null) {
      if (status == TransportStatus.connecting) {
        _beginEpoch(update.connectionEpoch);
      } else if (status == TransportStatus.connected) {
        if (_epoch != update.connectionEpoch) {
          _beginEpoch(update.connectionEpoch);
        }
        if (_supportedServer &&
            _attempt == null &&
            _state.phase != AuthPhase.authenticated) {
          _set(_idlePhase, error: _state.error);
          _armChallengeTimeout();
        }
      } else {
        _connectionLost();
      }
      return;
    }
    if (!session.isCurrent(update.connectionEpoch) ||
        update.roomId != null ||
        !_supportedServer) {
      return;
    }
    final event = update.event;
    if (event is ChallengeEvent) {
      if (!isValidAuthChallenge(event.challenge)) {
        _disconnectFor(AuthFailure.invalidServerEvent);
        return;
      }
      if (_attempt?.sentAfterSequence != null ||
          _state.phase == AuthPhase.authenticated) {
        _disconnectFor(AuthFailure.cancelled);
        return;
      }
      final interrupted = _attempt != null;
      _invalidateAttempt();
      _challenge = event.challenge;
      _challengeRevision++;
      _challengeTimer?.cancel();
      _set(_idlePhase, error: interrupted ? AuthFailure.cancelled : null);
      return;
    }
    final attempt = _attempt;
    final awaiting =
        attempt != null &&
        attempt.sentAfterSequence != null &&
        update.sequence > attempt.sentAfterSequence! &&
        _current(attempt);
    if (event is UpdateUserEvent) {
      final id = _userId(event.user);
      if (_state.phase == AuthPhase.authenticated) {
        if (!event.named || id != _state.userId) {
          _disconnectFor(AuthFailure.identityRejected);
        }
      } else if (awaiting && event.named && id == attempt.userId) {
        final name = attempt.username!;
        _invalidateAttempt();
        _set(AuthPhase.authenticated, username: name, userId: id);
      }
    } else if (awaiting &&
        event is NameTakenEvent &&
        (event.username.isEmpty ||
            authUserId(event.username) == attempt.userId)) {
      _disconnectFor(AuthFailure.identityRejected);
    } else if (awaiting && (event is ServerErrorEvent || event is PopupEvent)) {
      _disconnectFor(AuthFailure.identityRejected);
    } else if (event is MalformedServerEvent &&
        (event.record.eventType == 'challstr' ||
            ((awaiting || _state.phase == AuthPhase.authenticated) &&
                [
                  'updateuser',
                  'nametaken',
                ].contains(event.record.eventType)))) {
      _disconnectFor(AuthFailure.invalidServerEvent);
    }
  }

  String? _userId(String fullName) {
    if (fullName.isEmpty) return null;
    // Protocol USER starts with a rank symbol (space for no rank). Also accept
    // the legacy unprefixed ASCII spelling already supported by our decoder.
    final name = RegExp(r'^[a-zA-Z0-9]').hasMatch(fullName)
        ? fullName
        : fullName.substring(1);
    return authUserId(name.split('@').first);
  }

  void _beginEpoch(int epoch) {
    _invalidateAttempt();
    _challengeTimer?.cancel();
    _challenge = null;
    _challengeRevision++;
    _epoch = epoch;
    if (!_supportedServer) {
      _set(AuthPhase.unavailable, error: AuthFailure.unsupportedServer);
      return;
    }
    _set(AuthPhase.waitingChallenge);
    _armChallengeTimeout();
  }

  void _armChallengeTimeout() {
    _challengeTimer?.cancel();
    if (_challenge != null || session.status != TransportStatus.connected) {
      return;
    }
    final epoch = _epoch;
    _challengeTimer = Timer(challengeTimeout, () {
      if (!_disposed && _challenge == null && session.isCurrent(epoch)) {
        _disconnectFor(AuthFailure.challengeTimeout);
      }
    });
  }

  void _connectionLost() {
    if (_disposed) return;
    final interrupted =
        _attempt != null || _state.phase == AuthPhase.authenticated;
    _challengeTimer?.cancel();
    _challenge = null;
    _challengeRevision++;
    _invalidateAttempt();
    _set(
      AuthPhase.disconnected,
      error: _state.error ?? (interrupted ? AuthFailure.connectionLost : null),
    );
  }

  void _invalidateAttempt() {
    _confirmationTimer?.cancel();
    final attempt = _attempt;
    _attempt = null;
    _api.cancelPending();
    if (attempt != null && !attempt.completed.isCompleted) {
      attempt.completed.complete();
    }
  }

  void _disconnectFor(AuthFailure failure) {
    _challengeTimer?.cancel();
    _challenge = null;
    _challengeRevision++;
    _invalidateAttempt();
    _set(AuthPhase.disconnecting, error: failure);
    _disconnectWork ??= _disconnect();
  }

  Future<void> _disconnect() async {
    try {
      await session.disconnect();
    } finally {
      _disconnectWork = null;
      if (!_disposed) _set(AuthPhase.disconnected, error: _state.error);
    }
  }

  Future<void> cancel() async {
    final attempt = _attempt;
    if (_disposed || attempt == null) return;
    if (attempt.sentAfterSequence != null) {
      _disconnectFor(AuthFailure.cancelled);
    } else {
      _invalidateAttempt();
      _set(_idlePhase, error: AuthFailure.cancelled);
    }
    await _httpWork;
    await _disconnectWork;
  }

  void _set(
    AuthPhase phase, {
    AuthFailure? error,
    String? username,
    String? userId,
  }) {
    if (_disposed) return;
    _state = AuthState(phase, error: error, username: username, userId: userId);
    _changes.add(_state);
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    final mustDisconnect =
        _attempt?.sentAfterSequence != null ||
        _state.phase == AuthPhase.authenticated;
    _disposed = true;
    _challengeTimer?.cancel();
    _challenge = null;
    _invalidateAttempt();
    _state = const AuthState(AuthPhase.disposed);
    _changes.add(_state);
    return _disposal = _dispose(mustDisconnect);
  }

  Future<void> _dispose(bool mustDisconnect) async {
    await _subscription.cancel();
    await _api.dispose();
    await _httpWork;
    if (mustDisconnect) await session.disconnect();
    await _disconnectWork;
    await _changes.close();
  }
}
