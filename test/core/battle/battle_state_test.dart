import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_reducer.dart';
import 'package:pokemon_showdown_client/core/battle/requests/battle_request_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';

void main() {
  final corpus = jsonDecode(
    File('test/fixtures/battle/scenarios.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final setup = corpus['setups']['initialized-battle'];
  final requests =
      (jsonDecode(File('test/fixtures/battle/requests.json').readAsStringSync())
              as Map)['cases']
          as List;
  final room = setup['roomId'] as String;
  BattleState feed(BattleState state, String wire, {int epoch = 1}) {
    for (final record in parseServerMessage(wire)) {
      final event = decodeServerRecord(record);
      if (event != null) {
        state = reduceBattleEvent(state, event, connectionEpoch: epoch);
      }
    }
    return state;
  }

  BattleState ready() => feed(
    BattleState(roomId: room, connectionEpoch: 1),
    setup['receive'] as String,
  );
  BattleState lines(BattleState state, String text) =>
      feed(state, '>$room\n$text');
  BattleState request(BattleState state, String id) {
    final fixture = requests.firstWhere((c) => c['id'] == id) as Map;
    final payload = fixture.containsKey('rawPayload')
        ? fixture['rawPayload']
        : jsonEncode(fixture['payload']);
    return lines(state, '|request|$payload');
  }

  test(
    'corpus initialization creates typed immutable metadata and active slots',
    () {
      final state = ready();
      expect(state.phase, BattlePhase.started);
      expect(state.compatible, isTrue);
      expect(state.turn, setup['expect']['turn']);
      expect(state.players['p1']!.name, 'ExamplePlayer');
      expect(state.teamSizes, {'p1': 2, 'p2': 2});
      expect(state.active['p1']!.details, 'Pikachu, L80, M');
      expect(state.active['p2']!.health.maxHp, 100);
      expect(state.privateSide, isNull);
      expect(state.request, isNull);
      expect(() => state.active.clear(), throwsUnsupportedError);
      expect(() => state.players.clear(), throwsUnsupportedError);
      expect(() => state.teamSizes.clear(), throwsUnsupportedError);
      expect(() => state.log.clear(), throwsUnsupportedError);
    },
  );

  test(
    'switch and drag replace the active slot without inferring bench identity',
    () {
      final initial = ready();
      final state = lines(
        initial,
        '|drag|p1a: NewName|Snorlax, L80, tera:Normal|250/300 par|[from] move: Roar',
      );
      expect(state.active['p1']!.ident, 'p1a: NewName');
      expect(state.active['p1']!.teraType, 'Normal');
      expect(state.active['p1']!.health.status, PokemonStatus.par);
      expect(initial.active['p1']!.ident, 'p1a: Alpha');
      expect(state.active['p2'], same(initial.active['p2']));
    },
  );

  test('private request snapshot stays separate from public health and PP', () {
    final initial = request(ready(), 'move');
    final state = lines(
      initial,
      '|move|p1a: Alpha|Thunderbolt|p2a: Gamma\n|-damage|p1a: Alpha|50/100 par\n|cant|p1a: Alpha|par|Thunderbolt',
    );
    expect(state.active['p1']!.health.hp, 50);
    expect(state.privateSide!.pokemon.first.condition.hp, 200);
    expect(state.request!.active!.moves.first.pp, 15);
    expect(state.log.map((e) => e.cannotAct), [false, true]);
    expect(state.log.last.attemptedMove, 'Thunderbolt');
    expect(initial.log, isEmpty);
  });

  test(
    'requests are replaced and revision increases including invalid/null',
    () {
      var state = request(ready(), 'move');
      final first = state.request;
      state = request(state, 'same-rqid-changed');
      expect(state.request!.rqid, first!.rqid);
      expect(state.request!.moveSlots, isEmpty);
      expect(state.requestRevision, 2);
      state = request(state, 'broken-json');
      expect(state.request!.kind, BattleRequestKind.malformedRequest);
      state = request(state, 'clear');
      expect(state.request!.kind, BattleRequestKind.noRequest);
      expect(state.requestRevision, 4);
      state = request(state, 'move');
      expect(state.request!.moveSlots, [1]);
      expect(state.unsupported, isFalse);
    },
  );

  test('health/status/heal/sethp/faint/tera transitions apply in order', () {
    var state = lines(
      ready(),
      '|-damage|p1a: Alpha|50/100 par\n|-heal|p1a: Alpha|75/100 par',
    );
    expect(state.active['p1']!.health.hp, 75);
    state = lines(
      state,
      '|-curestatus|p1a: Alpha|par\n|-sethp|p1a: Alpha|40/100|p2a: Gamma|60/100|[from] move: Pain Split',
    );
    expect(state.active['p1']!.health.status, isNull);
    expect(state.active['p1']!.health.hp, 40);
    expect(state.active['p2']!.health.hp, 60);
    state = lines(
      state,
      '|-status|p2a: Gamma|slp\n|-terastallize|p1a: Alpha|Electric\n|faint|p2a: Gamma',
    );
    expect(state.active['p1']!.teraType, 'Electric');
    expect(state.active['p2']!.health.fainted, isTrue);
    expect(state.active['p2']!.health.hp, 0);
    expect(state.result, isNull);
  });

  test('sethp is atomic when second target is missing or malformed', () {
    for (final second in ['p2a: Wrong|30/100', 'p2a: Gamma|101/100']) {
      final initial = ready();
      final state = lines(initial, '|-sethp|p1a: Alpha|10/100|$second');
      expect(state.unsupported, isTrue);
      expect(state.active['p1']!.health.hp, 100);
      expect(state.active['p2']!.health.hp, 100);
    }
  });

  test(
    'unknown state, mode and malformed events stay blocked after request',
    () {
      for (final wire in [
        '|-boost|p1a: Alpha|atk|1',
        '|-transform|p1a: Alpha|p2a: Gamma',
        '|teampreview',
        '|gen|8',
        '|gametype|doubles',
        '|teamsize|p3|2',
        '|switch|p1b: Other|Ditto|100/100',
        '|-damage|p1a: Alpha|private-secret',
        '|turn|0',
        '|teamsize|p1|7',
      ]) {
        var state = lines(ready(), wire);
        state = request(state, 'move');
        expect(state.unsupported, isTrue, reason: wire);
        expect(state.compatible, isFalse);
      }
    },
  );

  test('decorative data and error messages cannot mutate field or acknowledge choice', () {
    final initial = request(ready(), 'move');
    final state = lines(
      initial,
      '|-nothing\n|-crit|p2a: Gamma\n|raw|<script>private</script>\n|html|<script>private</script>\n|uhtml|x|<b>text</b>\n|error|[Invalid choice] Example\n|popup|Example',
    );
    expect(state, same(initial));
    expect(state.log, isEmpty);
  });

  test('terminal result survives late request/start/init and deinit', () {
    for (final end in ['|win|ExamplePlayer', '|tie']) {
      final ended = lines(request(ready(), 'move'), end);
      expect(ended.phase, BattlePhase.finished);
      expect(ended.request, isNull);
      final later = request(
        lines(ended, '|start\n|init|battle\n|turn|99'),
        'move',
      );
      expect(later, same(ended));
      final closed = lines(later, '|deinit');
      expect(closed.phase, BattlePhase.closed);
      expect(closed.result, same(ended.result));
      expect(closed.result!.isTie, end == '|tie');
    }
  });

  test('deinit and stale do not fabricate a result or revive old requests', () {
    final initial = request(ready(), 'move');
    final closed = lines(initial, '|deinit');
    expect(closed.result, isNull);
    expect(closed.request, isNull);
    final stale = initial.markStale();
    expect(stale.stale, isTrue);
    expect(stale.request, isNull);
    expect(stale.result, isNull);
    expect(request(stale, 'move'), same(stale));
  });

  test('other room/global/epoch cannot change state', () {
    final initial = ready();
    expect(feed(initial, '>battle-other\n|win|Someone'), same(initial));
    expect(feed(initial, '|win|Someone'), same(initial));
    expect(feed(initial, '>$room\n|win|Someone', epoch: 2), same(initial));
  });

  test('duplicate init cannot clear sticky block; fresh context can', () {
    final blocked = lines(ready(), '|-future|x');
    expect(lines(blocked, '|init|battle').unsupported, isTrue);
    expect(ready().unsupported, isFalse);
  });

  test('log is bounded and chronological without synthesizing outcomes', () {
    var state = ready();
    for (var i = 0; i < maxBattleLogEntries + 5; i++) {
      state = lines(state, '|move|p1a: Alpha|Move $i|p2a: Gamma');
    }
    expect(state.log.length, maxBattleLogEntries);
    expect(state.log.first.action, 'Move 5');
    expect(state.active['p2']!.health.hp, 100);
  });

  // Execute projection-only slices; choice/send expectations belong to PR 4.
  for (final id in [
    'status-and-hp',
    'ordinary-turn',
    'forced-switch',
    'terastallize',
    'tie-is-terminal',
  ]) {
    test('corpus projection: $id', () {
      final scenario = (corpus['cases'] as List).firstWhere(
        (c) => c['id'] == id,
      );
      var state = ready();
      for (final step in scenario['steps']) {
        if (step.containsKey('receive')) state = feed(state, step['receive']);
        if (step.containsKey('requestFixture')) {
          state = request(state, step['requestFixture']);
        }
        final expected = step['expect'];
        if (expected == null) continue;
        if (expected.containsKey('turn')) expect(state.turn, expected['turn']);
        if (expected.containsKey('moveSlots')) {
          expect(state.request!.moveSlots, expected['moveSlots']);
        }
        if (expected.containsKey('switchSlots')) {
          expect(state.request!.switchSlots, expected['switchSlots']);
        }
        for (final key in ['publicOwnHp', 'opponentHp']) {
          if (expected.containsKey(key)) {
            final hp = state.active[key == 'publicOwnHp' ? 'p1' : 'p2']!.health;
            expect(hp.hp, expected[key]['value']);
            expect(hp.maxHp, expected[key]['max']);
          }
        }
        if (expected.containsKey('status')) {
          expect(state.active['p1']!.health.status?.name, expected['status']);
        }
        if (expected.containsKey('teraType')) {
          expect(state.active['p1']!.teraType, expected['teraType']);
        }
        if (expected.containsKey('result')) {
          expect(state.result!.isTie, expected['result']['kind'] == 'tie');
        }
      }
    });
  }
}
