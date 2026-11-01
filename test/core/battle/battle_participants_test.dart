import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_reducer.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

const room = 'battle-participants';
BattleState feed(
  BattleState state,
  String wire, {
  int epoch = 1,
  String id = room,
}) {
  for (final record in parseServerMessage('>$id\n$wire')) {
    final event = decodeServerRecord(record);
    if (event != null) {
      state = reduceBattleEvent(state, event, connectionEpoch: epoch);
    }
  }
  return state;
}

BattleState ready() => feed(
  BattleState(roomId: room, connectionEpoch: 1),
  '|init|battle\n|gen|9\n|gametype|singles\n|teamsize|p1|2\n|teamsize|p2|2\n|start\n|turn|1\n'
  '|switch|p1a: Alpha|Pikachu, L80|100/100 par\n|switch|p2a: Alpha|Snorlax, L80|100/100',
);
Map<String, dynamic> requestPayload() {
  final requests = jsonDecode(
    File('test/fixtures/battle/requests.json').readAsStringSync(),
  ) as Map;
  return jsonDecode(
    jsonEncode(
      (requests['cases'] as List).firstWhere(
        (c) => c['id'] == 'move',
      )['payload'],
    ),
  ) as Map<String, dynamic>;
}

BattleState request(BattleState state, Map<String, dynamic> payload) =>
    feed(state, '|request|${jsonEncode(payload)}');

void main() {
  test(
    'switch retains public evidence and return gets a fresh appearance ID',
    () {
      final initial = ready();
      final damaged = feed(
        initial,
        '|-damage|p1a: Alpha|40/100 par\n|-terastallize|p1a: Alpha|Electric',
      );
      final away = feed(damaged, '|switch|p1a: Beta|Snorlax, L80|100/100');
      final returned = feed(away, '|switch|p1a: Alpha|Pikachu, L80|80/100');
      expect(initial.roster.activeIds, {'p1': 1, 'p2': 2});
      expect(returned.roster.activeIds, {'p1': 4, 'p2': 2});
      expect(returned.roster.appearances[4]!.samePresentationIds, [1]);
      expect(returned.roster.appearances[1]!.pokemon.health.hp, 40);
      expect(returned.roster.appearances[1]!.pokemon.teraType, 'Electric');
      // No inference from the previous appearance, including its Tera/status.
      expect(returned.active['p1']!.health.hp, 80);
      expect(returned.active['p1']!.health.status, isNull);
      expect(returned.active['p1']!.teraType, isNull);
      expect(initial.active['p1']!.health.hp, 100);
      expect(damaged.roster.appearances.length, 2);
      expect(away.roster.activeIds['p1'], 3);
      expect(
        returned.teamSizes['p1'],
        2,
      ); // observations are not roster cardinality
    },
  );
  test(
    'same nickname on different species or sides does not merge observations',
    () {
      var state = feed(ready(), '|drag|p1a: Alpha|Snorlax, L80|90/100');
      expect(state.roster.appearances[3]!.samePresentationIds, isEmpty);
      state = feed(state, '|switch|p1a: Alpha|Pikachu, L80|80/100');
      state = feed(state, '|switch|p1a: Alpha|Pikachu, L80|70/100');
      expect(state.roster.appearances[5]!.samePresentationIds, [1, 4]);
      expect(state.roster.appearances.length, 5);
      expect(state.active['p2']!.health.hp, 100);
    },
  );
  test('faint and HP updates affect only current appearance and sethp stays atomic', () {
    final before = feed(ready(), '|switch|p1a: Beta|Snorlax, L80|100/100');
    final failed = feed(before, '|-sethp|p1a: Beta|20/100|p2a: Missing|30/100');
    expect(failed.unsupported, isTrue);
    expect(failed.roster, same(before.roster));
    final changed = feed(
      before,
      '|-sethp|p1a: Beta|20/100|p2a: Alpha|30/100\n|faint|p1a: Beta',
    );
    expect(changed.roster.appearances[3]!.pokemon.health.fainted, isTrue);
    expect(changed.roster.appearances[2]!.pokemon.health.hp, 30);
    expect(changed.roster.appearances[1]!.pokemon.health.hp, 100);
    expect(before.roster.appearances[3]!.pokemon.health.fainted, isFalse);
  });
  test('active status cure updates appearance and derived active view', () {
    final state = feed(ready(), '|-curestatus|p1a: Alpha|par|[msg]');
    expect(state.unsupported, isFalse);
    expect(state.active['p1']!.health.status, isNull);
    expect(state.roster.appearances[1]!.pokemon.health.status, isNull);
  });
  test('bench cure records evidence without rewriting historical status or request', () {
    final initial = request(ready(), requestPayload());
    final away = feed(initial, '|switch|p1a: Beta|Snorlax, L80|100/100');
    final state = feed(away, '|-curestatus|p1: Alpha|par|[msg]');
    expect(state.unsupported, isFalse);
    expect(state.roster.benchStatuses.single.candidateAppearanceIds, [1]);
    expect(state.roster.benchStatuses.single.mayReferToUnseenPokemon, isTrue);
    expect(state.roster.benchStatuses.single.cured, isTrue);
    expect(state.roster.benchStatuses.single.status.name, 'par');
    expect(state.roster.appearances[1]!.pokemon.health.status!.name, 'par');
    expect(state.privateSide, same(initial.privateSide));
    expect(state.request, same(initial.request));
    expect(state.roster.appearances.length, 3);
  });
  test('bench nickname can match multiple historical appearances or unseen Pokemon', () {
    var state = feed(
      ready(),
      '|switch|p1a: Alpha|Snorlax, L80|100/100\n|switch|p1a: Beta|Ditto, L80|100/100',
    );
    state = feed(
      state,
      '|-curestatus|p1: Alpha|par\n|-curestatus|p2: Unseen|slp',
    );
    expect(state.roster.benchStatuses.first.candidateAppearanceIds, [1, 3]);
    expect(state.roster.benchStatuses.last.candidateAppearanceIds, isEmpty);
    expect(state.roster.appearances.length, 4);
    expect(state.active['p2']!.details, 'Snorlax, L80');
    expect(state.roster.activeIds, {'p1': 4, 'p2': 2});
  });
  test('active appearance is not assigned a bench report by nickname', () {
    final state = feed(ready(), '|-curestatus|p1: Alpha|par');
    expect(state.roster.benchStatuses.single.candidateAppearanceIds, isEmpty);
    expect(state.active['p1']!.health.status!.name, 'par');
  });
  test('malformed, other-mode and legacy cureteam keep safeguards', () {
    for (final wire in [
      '|-curestatus|p3: Alpha|par',
      '|-curestatus|p1b: Alpha|par',
      '|-curestatus|p1: Alpha|bad',
      '|-curestatus|p1: |par',
      '|-status|p1: Alpha|par',
      '|-cureteam|p1a: Alpha',
      '|replace|p1a: Alpha|Zoroark|100/100',
      '|-transform|p1a: Alpha|p2a: Alpha',
    ]) {
      final initial = ready();
      final state = feed(initial, wire);
      expect(state.unsupported, isTrue, reason: wire);
      expect(state.roster, same(initial.roster));
    }
  });
  test(
    'private active reference is revision-scoped and not a nickname join',
    () {
      final payload = requestPayload();
      payload['side']['pokemon'][0]['ident'] = 'p1: Secret true name';
      payload['side']['pokemon'][0]['details'] = 'Zoroark, L80';
      final first = request(ready(), payload);
      expect(first.privateActiveReference!.appearanceId, 1);
      expect(first.privateActiveReference!.requestSlot, 1);
      expect(first.privateActiveReference!.requestRevision, 1);
      expect(first.active['p1']!.details, 'Pikachu, L80');
      expect(first.roster.appearances.length, 2);
      expect(first.active['p1']!.health.hp, 100); // private snapshot says 200
      final ordered = (payload['side']['pokemon'] as List).reversed.toList();
      payload['side']['pokemon'] = ordered;
      final next = request(first, payload);
      expect(next.privateActiveReference!.requestSlot, 2);
      expect(next.privateActiveReference!.requestRevision, 2);
      expect(next.privateActiveReference!.appearanceId, 1);
      expect(first.privateActiveReference!.requestSlot, 1);
    },
  );
  test('p2 private side binds only its own active appearance', () {
    final payload = requestPayload();
    payload['side']['id'] = 'p2';
    for (final p in payload['side']['pokemon']) {
      p['ident'] = (p['ident'] as String).replaceFirst('p1:', 'p2:');
    }
    final state = request(ready(), payload);
    expect(state.privateActiveReference!.appearanceId, 2);
    expect(state.privateActiveReference!.sideId, 'p2');
    expect(state.roster.appearances.length, 2);
    expect(
      feed(state, '|switch|p1a: Beta|Ditto|50/100').privateActiveReference,
      same(state.privateActiveReference),
    );
    expect(
      feed(state, '|switch|p2a: Beta|Ditto|50/100').privateActiveReference,
      isNull,
    );
  });
  test('non-unique active private flags do not invent a slot association', () {
    for (final active in [false, true]) {
      final payload = requestPayload();
      for (final p in payload['side']['pokemon']) {
        p['active'] = active;
      }
      expect(request(ready(), payload).privateActiveReference, isNull);
    }
  });
  test('switch, request clear, malformed input, terminal and stale revoke private reference', () {
    final initial = request(ready(), requestPayload());
    for (final wire in [
      '|switch|p1a: Beta|Ditto|100/100',
      '|request|null',
      '|request|{"wait":true}',
      '|request|broken',
      '|win|Someone',
      '|deinit',
      '|-futuremechanic|opaque',
    ]) {
      expect(feed(initial, wire).privateActiveReference, isNull, reason: wire);
    }
    expect(initial.markStale().privateActiveReference, isNull);
    expect(initial.markStale().privateSide, same(initial.privateSide));
    // A request arriving before any public switch does not create public data.
    final noPublic = feed(
      BattleState(roomId: room, connectionEpoch: 1),
      '|init|battle\n|gen|9\n|gametype|singles\n|start',
    );
    final state = request(noPublic, requestPayload());
    expect(state.roster.appearances, isEmpty);
    expect(state.privateActiveReference, isNull);
  });
  test('wrong room, epoch, stale and terminal do not change roster', () {
    final initial = ready();
    const wire = '|switch|p1a: Beta|Ditto|100/100\n|-curestatus|p1: Unseen|par';
    expect(feed(initial, wire, epoch: 2), same(initial));
    expect(feed(initial, wire, id: 'battle-other'), same(initial));
    final stale = initial.markStale();
    expect(feed(stale, wire), same(stale));
    final terminal = feed(initial, '|tie');
    expect(feed(terminal, wire), same(terminal));
    expect(terminal.roster, same(initial.roster));
  });
  test(
    'action log identifies appearance rather than merging same nicknames',
    () {
      final state = feed(
        ready(),
        '|move|p1a: Alpha|Thunderbolt|p2a: Alpha\n'
        '|switch|p1a: Alpha|Snorlax, L80|100/100\n|cant|p1a: Alpha|slp',
      );
      expect(state.log.map((e) => e.actorAppearanceId), [1, 3]);
      expect(state.log.map((e) => e.actor), ['p1a: Alpha', 'p1a: Alpha']);
    },
  );
  test('all evidence collections are immutable', () {
    final state = feed(
      ready(),
      '|switch|p1a: Alpha|Pikachu, L80|100/100\n|-curestatus|p1: Alpha|par',
    );
    expect(() => state.roster.appearances.clear(), throwsUnsupportedError);
    expect(() => state.roster.activeIds.clear(), throwsUnsupportedError);
    expect(() => state.active.clear(), throwsUnsupportedError);
    expect(() => state.roster.benchStatuses.clear(), throwsUnsupportedError);
    expect(
      () => state.roster.appearances[3]!.samePresentationIds.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => state.roster.benchStatuses.single.candidateAppearanceIds.clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'history is bounded, active slots survive and evicted IDs are never reused',
    () {
      var state = feed(
        ready(),
        '|switch|p1a: Alpha|Pikachu, L80|100/100\n|-curestatus|p1: Alpha|par',
      );
      final saved = state;
      for (var i = 0; i < maxBattleAppearances + 10; i++) {
        state = feed(state, '|switch|p1a: Alpha|Pikachu, L80|100/100');
      }
      expect(state.roster.appearances.length, maxBattleAppearances);
      expect(state.roster.historyTruncated, isTrue);
      expect(state.roster.activeIds['p2'], 2);
      expect(state.roster.appearances.containsKey(2), isTrue);
      expect(state.roster.appearances.containsKey(1), isFalse);
      expect(state.roster.activeIds['p1'], greaterThan(maxBattleAppearances));
      for (final appearance in state.roster.appearances.values) {
        expect(
          appearance.samePresentationIds.every(
            state.roster.appearances.containsKey,
          ),
          isTrue,
        );
      }
      expect(state.roster.benchStatuses.single.candidateAppearanceIds, isEmpty);
      expect(saved.roster.appearances[1], isNotNull);
      for (var i = 0; i < maxBenchStatusObservations + 10; i++) {
        state = feed(state, '|-curestatus|p2: Unknown$i|slp');
      }
      expect(state.roster.benchStatuses.length, maxBenchStatusObservations);
      expect(state.roster.benchStatuses.last.ident, 'p2: Unknown137');
    },
  );
}
