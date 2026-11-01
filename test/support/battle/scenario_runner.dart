import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/decisions/battle_decision_controller.dart';
import 'package:pokemon_showdown_client/core/battle/requests/battle_request_kind.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_phase.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../../core/transport/support/fake_socket_channel.dart';

/// Test-only wire -> transport -> session -> controller interpreter.
/// Expectations never enter the production pipeline. Unknown DSL fields fail.
final class BattleScenarioRunner {
  BattleScenarioRunner(this.setups, this.requests);
  final Map<String, dynamic> setups;
  final Map<String, Map<String, dynamic>> requests;
  final _sockets = <FakeSocketChannel>[];
  final _captured = <String, CapturedBattleChoice?>{};
  final _pending = <SessionUpdate>[];
  final _delivery = StreamController<SessionUpdate>.broadcast(sync: true);
  late ShowdownSession _session;
  late BattleDecisionController _controller;
  StreamSubscription<SessionUpdate>? _subscription;
  bool _hold = false;
  int? _sourceEpoch;
  int _sendCheckpoint = 0;
  late String _room;

  List<Object?> get _sent => [for (final s in _sockets) ...s.sink.sent];

  static void keys(Map value, Set<String> allowed) {
    final unknown = value.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) throw FormatException('Unknown fields: $unknown');
  }

  static Map<String, Map<String, dynamic>> index(List<dynamic> cases) {
    final result = <String, Map<String, dynamic>>{};
    for (final raw in cases) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final id = entry['id'] as String;
      if (result.containsKey(id)) throw FormatException('Duplicate id: $id');
      result[id] = entry;
    }
    return result;
  }

  Future<void> run(Map<String, dynamic> scenario) async {
    keys(scenario, {'id', 'setup', 'steps', 'note'});
    final setup = setups[scenario['setup']] as Map<String, dynamic>?;
    if (setup == null) throw const FormatException('Unknown setup');
    keys(setup, {'roomId', 'connectionEpoch', 'receive', 'expect'});
    _room = setup['roomId'] as String;
    _session = ShowdownSession(
      transport: ShowdownTransport(
        channelFactory: (_) {
          final socket = FakeSocketChannel();
          _sockets.add(socket);
          socket.handshake.complete();
          return socket;
        },
      ),
    );
    try {
      await _session.connect(Uri.parse('wss://example.test'));
      await _drain();
      expect(_session.connectionEpoch, setup['connectionEpoch']);
      _subscription = _session.updates.listen((update) {
        final forwarded = _sourceEpoch != null && update.event != null
            ? SessionUpdate.event(
                _sourceEpoch!,
                update.event!,
                roomId: update.roomId,
                sequence: update.sequence,
              )
            : update;
        if (_hold) {
          _pending.add(forwarded);
        } else {
          _delivery.add(forwarded);
        }
      });
      _controller = BattleDecisionController(
        session: _session,
        roomId: _room,
        updates: _delivery.stream,
      );
      try {
        await _receive(setup['receive'] as String);
        _check(setup['expect'] as Map<String, dynamic>);
        var ordinal = 0;
        for (final raw in scenario['steps'] as List) {
          ordinal++;
          try {
            await _step(Map<String, dynamic>.from(raw as Map));
          } catch (error) {
            throw TestFailure('${scenario['id']} step $ordinal: $error');
          }
        }
        if (_hold || _pending.isNotEmpty) {
          throw const FormatException('Undrained updates');
        }
      } finally {
        await _controller.dispose();
      }
    } finally {
      await _subscription?.cancel();
      await _delivery.close();
      await _session.dispose();
      for (final socket in _sockets) {
        await socket.incoming.close();
      }
    }
  }

  Future<void> _step(Map<String, dynamic> step) async {
    const operations = {
      'receive',
      'requestFixture',
      'choose',
      'captureChoice',
      'submitCaptured',
      'disconnect',
      'connectEpoch',
      'enqueueRequestFixture',
      'drainUpdates',
      'expect',
    };
    keys(step, {...operations, 'epoch'});
    final actions = step.keys.where(operations.contains).toList();
    if (actions.length != 1) {
      throw const FormatException('One operation required');
    }
    final action = actions.single;
    if (step.containsKey('epoch') && action != 'requestFixture') {
      throw const FormatException('epoch only applies to requestFixture');
    }
    switch (action) {
      case 'receive':
        await _receive(step[action] as String);
      case 'requestFixture':
        await _receive(
          _request(step[action] as String),
          epoch: step['epoch'] as int?,
        );
      case 'choose':
        final choice = _choice(step[action] as Map<String, dynamic>);
        final captured = _controller.capture(choice);
        if (captured != null) _controller.submit(captured);
      case 'captureChoice':
        final data = Map<String, dynamic>.from(step[action] as Map);
        final name = data.remove('as') as String;
        if (_captured.containsKey(name)) {
          throw const FormatException('Duplicate capture');
        }
        _captured[name] = _controller.capture(_choice(data));
        expect(
          _captured[name],
          isNotNull,
          reason: 'Capture must be actionable before testing staleness',
        );
      case 'submitCaptured':
        final name = step[action] as String;
        if (!_captured.containsKey(name)) {
          throw const FormatException('Unknown capture');
        }
        final captured = _captured[name];
        if (captured != null) _controller.submit(captured);
      case 'disconnect':
        expect(step[action], true);
        await _session.disconnect();
        await _drain();
      case 'connectEpoch':
        await _session.connect(Uri.parse('wss://example.test'));
        await _drain();
        expect(_session.connectionEpoch, step[action]);
      case 'enqueueRequestFixture':
        if (_hold) throw const FormatException('Already holding updates');
        _hold = true;
        final before = _session.latestUpdateSequence;
        await _receive(_request(step[action] as String));
        expect(_session.latestUpdateSequence, greaterThan(before));
        expect(_pending, isNotEmpty);
      case 'drainUpdates':
        expect(step[action], true);
        if (!_hold) throw const FormatException('No held updates');
        _hold = false;
        for (final update in _pending) {
          _delivery.add(update);
        }
        _pending.clear();
        await _drain();
      case 'expect':
        _check(step[action] as Map<String, dynamic>);
    }
  }

  BattleChoice _choice(Map<String, dynamic> choice) {
    keys(choice, {'kind', 'slot', 'terastallize'});
    final slot = choice['slot'] as int;
    return switch (choice['kind']) {
      'move' => BattleChoice.move(
        slot,
        terastallize: choice['terastallize'] as bool? ?? false,
      ),
      'switch' when !choice.containsKey('terastallize') =>
        BattleChoice.switchTo(slot),
      _ => throw const FormatException('Unknown choice'),
    };
  }

  String _request(String id) {
    final fixture = requests[id];
    if (fixture == null) throw FormatException('Unknown request: $id');
    if (fixture.containsKey('rawPayload') == fixture.containsKey('payload')) {
      throw const FormatException('Exactly one payload required');
    }
    final payload = fixture.containsKey('rawPayload')
        ? fixture['rawPayload'] as String
        : jsonEncode(fixture['payload']);
    return '>$_room\n|request|$payload';
  }

  Future<void> _receive(String wire, {int? epoch}) async {
    _sourceEpoch = epoch;
    _sockets.last.incoming.add(wire);
    await _drain();
    _sourceEpoch = null;
  }

  // Domain contract labels combine independent controller, state and request
  // enums. This is not a second production state machine and never drives it.
  String get _phase {
    final state = _controller.state;
    if (state.phase == BattlePhase.finished) return 'finished';
    if (state.phase == BattlePhase.closed) return 'closed';
    if (state.stale) return 'disconnected';
    if (state.unsupported) return 'unsupportedState';
    final kind = state.request?.kind;
    if (kind == null || kind == BattleRequestKind.noRequest) return 'noRequest';
    if (kind == BattleRequestKind.wait) return 'wait';
    if (kind == BattleRequestKind.malformedRequest) return 'malformedRequest';
    if (kind == BattleRequestKind.unsupportedRequest) {
      return 'unsupportedRequest';
    }
    return _controller.phase.name;
  }

  void _check(Map<String, dynamic> expected) {
    final state = _controller.state;
    final own = state.active['p1'];
    final opponent = state.active['p2'];
    final actual = <String, dynamic>{
      'phase': _phase,
      'controllerPhase': _controller.phase.name,
      'turn': state.turn,
      'requestRevision': state.requestRevision,
      'moveSlots': state.request?.moveSlots ?? <int>[],
      'switchSlots': state.request?.switchSlots ?? <int>[],
      'requestKind': state.request?.kind.name,
      'requestAvailable': _controller.canChoose,
      'canChoose': _controller.canChoose,
      'canTerastallize': state.request?.canTerastallize ?? false,
      'sendCount': _sent.length,
      'stale': state.stale,
      'unsupported': state.unsupported,
      'activeIdent': own?.ident,
      'activeDetails': own?.details,
      'teraType': own?.teraType,
      'status': own?.health.status?.name,
      'logCount': state.log.length,
      'error': _controller.choiceRejected ? 'invalidChoice' : null,
      'result': state.result == null
          ? null
          : state.result!.isTie
          ? {'kind': 'tie'}
          : {'kind': 'win', 'winner': state.result!.winner},
      'publicOwnHp': own == null
          ? null
          : {
              'value': own.health.hp,
              'max': own.health.maxHp,
              'precision': 'publicScale',
            },
      'opponentHp': opponent == null
          ? null
          : {
              'value': opponent.health.hp,
              'max': opponent.health.maxHp,
              'precision': 'publicScale',
            },
    };
    keys(expected, {...actual.keys, 'send'});
    for (final entry in expected.entries) {
      if (entry.key == 'send') {
        expect(_sent.sublist(_sendCheckpoint), [
          entry.value,
        ], reason: 'New wire sends');
        _sendCheckpoint = _sent.length;
      } else {
        expect(actual[entry.key], entry.value, reason: entry.key);
      }
    }
  }
}

Future<void> _drain() async {
  // Drain transport/router/session microtasks and the controller's zero timer.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
