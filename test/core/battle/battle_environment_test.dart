import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_reducer.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

const room = 'battle-environment';
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
  '|init|battle\n|gen|9\n|gametype|singles\n|start\n|turn|1\n'
  '|switch|p1a: A|Pikachu|100/100\n|switch|p2a: B|Snorlax|100/100',
);

void main() {
  for (final weather in battleWeather) {
    test(
      '$weather starts, persists without guessed expiry, upkeeps and ends',
      () {
        final initial = ready();
        var s = feed(
          initial,
          '|-weather|$weather|[from] ability: Drizzle|[of] p2a: B',
        );
        expect(s.environment.weather!.id, weather);
        expect(s.environment.weather!.startedTurn, 1);
        expect(s.environment.weather!.sourceEffect, 'ability: Drizzle');
        expect(s.environment.weather!.sourceIdent, 'p2a: B');
        s = feed(
          s,
          '|turn|20\n|-weather|$weather|[upkeep]\n|-weather|$weather|[upkeep]',
        );
        expect(s.environment.weather!.startedTurn, 1);
        expect(s.environment.weather!.lastUpkeepTurn, 20);
        expect(s.environment.weather!.sourceEffect, 'ability: Drizzle');
        expect(initial.environment.weather, isNull);
        expect(s.unsupported, isFalse);
        s = feed(s, '|-weather|none');
        expect(s.environment.weather, isNull);
        expect(s.unsupported, isFalse);
      },
    );
  }
  test('weather replacement resets observation, mismatching upkeep blocks atomically', () {
    final first = feed(ready(), '|-weather|RainDance');
    final replaced = feed(first, '|turn|3\n|-weather|Snowscape');
    expect(replaced.environment.weather!.id, 'snowscape');
    expect(replaced.environment.weather!.startedTurn, 3);
    expect(replaced.environment.weather!.lastUpkeepTurn, isNull);
    final bad = feed(replaced, '|-weather|RainDance|[upkeep]');
    expect(bad.unsupported, isTrue);
    expect(identical(bad.environment, replaced.environment), isTrue);
    expect(feed(ready(), '|-weather|RainDance|[upkeep]').unsupported, isTrue);
  });
  for (final terrain in battleTerrains) {
    test(
      '$terrain replaces terrain without an end event, unrelated end is harmless',
      () {
        final previous = terrain == 'grassyterrain'
            ? 'electricterrain'
            : 'grassyterrain';
        var s = feed(
          ready(),
          '|-fieldstart|$previous\n|-fieldstart|move: Trick Room',
        );
        s = feed(
          s,
          '|turn|2\n|-fieldstart|$terrain|[from] ability: Hadron Engine|[of] p1a: A',
        );
        expect(s.environment.terrain!.id, terrain);
        expect(s.environment.terrain!.startedTurn, 2);
        expect(s.environment.terrain!.sourceIdent, 'p1a: A');
        s = feed(s, '|-fieldend|$previous');
        expect(s.environment.terrain!.id, terrain);
        expect(s.environment.fields.keys, ['trickroom']);
        s = feed(s, '|turn|30\n|-fieldend|$terrain\n|-fieldend|$terrain');
        expect(s.environment.terrain, isNull);
        expect(s.environment.fields.keys, ['trickroom']);
        expect(s.unsupported, isFalse);
      },
    );
  }
  test('rooms and Gravity coexist, retain metadata and end independently', () {
    var s = ready();
    for (final id in battleFieldConditions) {
      s = feed(s, '|-fieldstart|$id|[of] p1a: A');
    }
    expect(s.environment.fields.keys.toSet(), battleFieldConditions);
    s = feed(
      s,
      '|turn|20\n|switch|p1a: C|Snorlax|100/100\n|-fieldend|move: Magic Room|[of] p1: A',
    );
    expect(s.environment.fields.keys.toSet(), {
      'gravity',
      'trickroom',
      'wonderroom',
    });
    expect(s.environment.fields['gravity']!.startedTurn, 1);
    expect(s.unsupported, isFalse);
  });
  for (final entry in battleSideConditions.entries) {
    test(
      '${entry.key} layers, restart, explicit removal and sides stay independent',
      () {
        var s = ready();
        for (var layer = 1; layer <= entry.value; layer++) {
          s = feed(s, '|-sidestart|p1: Player|${entry.key}');
          expect(s.environment.p1[entry.key]!.layers, layer);
          expect(s.environment.p2, isEmpty);
        }
        final duplicate = feed(
          s,
          '|turn|2\n|-sidestart|p1: Renamed|${entry.key}',
        );
        if (entry.value > 1) {
          expect(duplicate.unsupported, isTrue);
          expect(duplicate.environment.p1[entry.key]!.layers, entry.value);
        } else {
          expect(duplicate.unsupported, isFalse);
          expect(duplicate.environment.p1[entry.key]!.layers, 1);
          expect(duplicate.environment.p1[entry.key]!.startedTurn, 2);
        }
        s = feed(
          s,
          '|-sidestart|p2|${entry.key}\n|-sideend|p1: Player|${entry.key}|[from] move: Defog|[of] p2a: B',
        );
        expect(s.environment.p1, isEmpty);
        expect(s.environment.p2[entry.key]!.layers, 1);
        expect(s.unsupported, isFalse);
      },
    );
  }
  test('Court Change swaps all supported conditions and preserves layers and start times', () {
    var s = feed(
      ready(),
      '|-weather|RainDance\n|-fieldstart|move: Electric Terrain',
    );
    for (final entry in battleSideConditions.entries) {
      s = feed(s, '|-sidestart|p1: Player|${entry.key}');
      if (entry.value > 1) s = feed(s, '|-sidestart|p1: Player|${entry.key}');
    }
    s = feed(
      s,
      '|turn|2\n|-sidestart|p2: Opponent|Reflect|[from] move: Reflect|[of] p2a: B',
    );
    final before = s.environment;
    s = feed(s, '|-swapsideconditions\n|-activate|p1a: A|move: Court Change');
    expect(s.environment.p1, before.p2);
    expect(s.environment.p2, before.p1);
    expect(s.environment.p1['reflect']!.startedTurn, 2);
    expect(s.environment.p2['spikes']!.layers, 2);
    expect(s.environment.p2['spikes']!.startedTurn, 1);
    expect(s.environment.p1['reflect']!.sourceIdent, 'p2a: B');
    expect(s.environment.weather, before.weather);
    expect(s.environment.terrain, before.terrain);
    expect(s.unsupported, isFalse);
    final back = feed(s, '|-swapsideconditions');
    expect(back.environment.p1, before.p1);
    expect(back.environment.p2, before.p2);
    expect(
      feed(s, '|-activate|p1a: Missing|move: Court Change').unsupported,
      isTrue,
    );
  });
  test(
    'Court Change with an empty side moves conditions, empty swap is harmless',
    () {
      var s = feed(
        ready(),
        '|-swapsideconditions\n|-sidestart|p2|Spikes\n|-swapsideconditions',
      );
      expect(s.environment.p1['spikes']!.layers, 1);
      expect(s.environment.p2, isEmpty);
      s = feed(s, '|-sideend|p1|Spikes|[from] move: Rapid Spin|[of] p1a: A');
      expect(s.environment.p1, isEmpty);
      expect(s.unsupported, isFalse);
    },
  );
  test('activations are bounded observations, never permanent field conditions', () {
    var s = ready();
    for (var i = 0; i < maxFieldActivations + 2; i++) {
      s = feed(
        s,
        '|turn|${i + 1}\n|-fieldactivate|move: ${i.isEven ? 'Perish Song' : 'Teatime'}',
      );
    }
    expect(s.environment.activations.length, maxFieldActivations);
    expect(s.environment.activations.first.turn, 3);
    expect(s.environment.activations.last.id, 'teatime');
    expect(s.environment.fields, isEmpty);
    expect(s.environment.terrain, isNull);
    expect(s.unsupported, isFalse);
    // Perish Song's counters remain explicitly unsupported from PR3.
    expect(feed(s, '|-start|p1a: A|perish3').unsupported, isTrue);
  });
  test('Pokemon changes, turn and requests preserve environment and previous snapshots', () {
    final s = feed(
      ready(),
      '|-weather|RainDance\n|-fieldstart|move: Gravity\n|-fieldstart|move: Misty Terrain\n|-sidestart|p1|Spikes',
    );
    final next = feed(
      s,
      '|switch|p1a: C|Snorlax|100/100\n|drag|p2a: D|Pikachu|100/100\n|faint|p1a: C\n|turn|30\n|request|null',
    );
    expect(identical(next.environment, s.environment), isTrue);
    expect(next.environment.p1['spikes']!.layers, 1);
    expect(next.unsupported, isFalse);
    expect(feed(next, '|-sideend|p1|Spikes').environment.p1, isEmpty);
    expect(s.environment.p1['spikes']!.layers, 1);
  });
  test('malformed and unsupported observations are atomic and sticky', () {
    final s = feed(ready(), '|-weather|RainDance\n|-sidestart|p1|Spikes');
    for (final wire in [
      '|-weather|Hail',
      '|-weather|PrimordialSea',
      '|-weather|FutureWeather',
      '|-weather|none|[upkeep]',
      '|-weather|RainDance|[upkeep]|[upkeep]',
      '|-weather|RainDance|[from] ability: Drizzle|[upkeep]',
      '|-weather|RainDance|[from] ability: Drizzle|[from] ability: Drought',
      '|-weather|RainDance|[of] p3a: X',
      '|-weather|RainDance|[from] ',
      '|-weather|RainDance|[mystery]',
      '|-weather|RainDance|[upkeep]|extra',
      '|-fieldstart|move: Future Field',
      '|-fieldstart|move: Trick Room|[persistent]',
      '|-fieldstart|move: Trick Room|[upkeep]',
      '|-fieldend|move: Trick Room|extra',
      '|-fieldactivate|move: Fairy Lock',
      '|-fieldactivate|Delta Stream',
      '|-sidestart|p3: X|Spikes',
      '|-sidestart|p1a: A|Spikes',
      '|-sidestart|p1: |Spikes',
      '|-sidestart|p1|G-Max Steelsurge',
      '|-sideend|p1|Unknown',
      '|-sidestart|p1|Spikes|4',
      '|-swapsideconditions|p1',
      '|-activate|p1a: A|move: Court Change|extra',
      '|-activate|p1a: A|move: Other',
    ]) {
      final bad = feed(s, wire);
      expect(bad.unsupported, isTrue, reason: wire);
      expect(identical(bad.environment, s.environment), isTrue, reason: wire);
      expect(feed(bad, '|request|null').unsupported, isTrue);
    }
  });
  test('wrong room/epoch, stale, closed and finished states ignore environment events', () {
    final s = ready();
    const wire = '|-weather|RainDance';
    expect(identical(feed(s, wire, epoch: 2), s), isTrue);
    expect(identical(feed(s, wire, id: 'battle-other'), s), isTrue);
    for (final state in [
      s.markStale(),
      feed(s, '|win|Alice'),
      feed(s, '|deinit'),
    ]) {
      expect(identical(feed(state, wire), state), isTrue);
    }
  });
  test('environment collections defensively copy and expose no mutation', () {
    const condition = EnvironmentCondition(id: 'spikes', startedTurn: 1);
    final fields = {'gravity': condition};
    final sides = {'spikes': condition};
    final activations = [const FieldActivation(id: 'teatime', turn: 1)];
    final environment = BattleEnvironment(
      fields: fields,
      p1: sides,
      p2: sides,
      activations: activations,
    );
    fields.clear();
    sides.clear();
    activations.clear();
    expect(environment.fields.length, 1);
    expect(environment.p1.length, 1);
    expect(environment.p2.length, 1);
    expect(environment.activations.length, 1);
    expect(() => environment.fields.clear(), throwsUnsupportedError);
    expect(() => environment.p1.clear(), throwsUnsupportedError);
    expect(() => environment.p2.clear(), throwsUnsupportedError);
    expect(() => environment.activations.clear(), throwsUnsupportedError);
  });
}
