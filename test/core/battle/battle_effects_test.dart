import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/state/pokemon_effects.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_reducer.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

const room = 'battle-effects';
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
PokemonEffects own(BattleState s) => s.active['p1']!.effects;

void main() {
  for (final stat in battleStats) {
    test('$stat reported stages clamp, set and invert without mutating history', () {
      final initial = ready();
      var state = feed(
        initial,
        '|-boost|p1a: A|$stat|6\n|-boost|p1a: A|$stat|2',
      );
      expect(own(state).boosts, {stat: 6});
      state = feed(
        state,
        '|-unboost|p1a: A|$stat|6\n|-unboost|p1a: A|$stat|6\n|-unboost|p1a: A|$stat|1',
      );
      expect(own(state).boosts, {stat: -6});
      state = feed(state, '|-setboost|p1a: A|$stat|-3\n|-invertboost|p1a: A');
      expect(own(state).boosts, {stat: 3});
      expect(own(initial).boosts, isEmpty);
      expect(state.unsupported, isFalse);
    });
  }
  test(
    'selective and all-stat exchange/copy preserve donor and unrelated stats',
    () {
      var s = feed(
        ready(),
        '|-boost|p1a: A|atk|2\n|-unboost|p1a: A|spe|1\n|-boost|p2a: B|def|3',
      );
      s = feed(s, '|-swapboost|p1a: A|p2a: B|atk, def|[from] move: Guard Swap');
      expect(own(s).boosts, {'def': 3, 'spe': -1});
      expect(s.active['p2']!.effects.boosts, {'atk': 2});
      s = feed(s, '|-copyboost|p2a: B|p1a: A|[from] move: Psych Up');
      expect(s.active['p2']!.effects.boosts, own(s).boosts);
      s = feed(s, '|-setboost|p2a: B|spe|5\n|-swapboost|p1a: A|p2a: B');
      expect(own(s).boosts['spe'], 5);
      expect(s.active['p2']!.effects.boosts['spe'], -1);
    },
  );
  test('all four clear operations preserve effects', () {
    final s = feed(
      ready(),
      '|-boost|p1a: A|atk|2\n|-unboost|p1a: A|def|2\n|-start|p1a: A|Substitute\n|-boost|p2a: B|spe|1',
    );
    expect(
      own(feed(s, '|-clearpositiveboost|p1a: A|p2a: B|move: Spectral Thief'))
          .boosts,
      {'def': -2},
    );
    expect(own(feed(s, '|-clearnegativeboost|p1a: A|[silent]')).boosts, {
      'atk': 2,
    });
    expect(own(feed(s, '|-clearboost|p1a: A')).boosts, isEmpty);
    final all = feed(s, '|-clearallboost');
    expect(all.active.values.every((p) => p.effects.boosts.isEmpty), isTrue);
    expect(own(all).volatiles, {'substitute': null});
  });
  for (final effect in persistentEffects) {
    test(
      '$effect has explicit end, no guessed timer, preserved by HP/status/Tera',
      () {
        final extra = effect == 'disable' ? '|Thunderbolt' : '';
        var s = feed(ready(), '|-start|p1a: A|$effect$extra');
        s = feed(
          s,
          '|turn|8\n|-damage|p1a: A|90/100\n|-status|p1a: A|par\n|-terastallize|p1a: A|Electric',
        );
        expect(own(s).volatiles.containsKey(effect), isTrue);
        if (effect == 'disable') {
          expect(own(s).volatiles[effect], 'Thunderbolt');
        }
        s = feed(s, '|-end|p1a: A|$effect|[silent]');
        expect(own(s).volatiles, isEmpty);
        expect(s.unsupported, isFalse);
      },
    );
  }
  test(
    'Protect expires on advancing turn, Destiny Bond on own move or cant',
    () {
      final s = feed(
        ready(),
        '|-singleturn|p1a: A|move: Protect\n|-singlemove|p1a: A|Destiny Bond',
      );
      expect(own(feed(s, '|turn|1')).volatiles.length, 2);
      final next = feed(s, '|turn|2\n|move|p2a: B|Tackle|p1a: A');
      expect(own(next).volatiles, {'destinybond': null});
      expect(own(feed(next, '|move|p1a: A|Tackle|p2a: B')).volatiles, isEmpty);
      expect(own(feed(next, '|cant|p1a: A|par')).volatiles, isEmpty);
    },
  );
  for (final change in ['switch', 'drag', 'faint']) {
    test(
      '$change clears active effects while switch preserves historical snapshot',
      () {
        final s = feed(
          ready(),
          '|-boost|p1a: A|atk|2\n|-start|p1a: A|Substitute',
        );
        final next = feed(
          s,
          change == 'faint'
              ? '|faint|p1a: A'
              : '|$change|p1a: C|Snorlax|100/100',
        );
        expect(own(next).boosts, isEmpty);
        expect(own(next).volatiles, isEmpty);
        if (change != 'faint') {
          expect(next.roster.appearances[1]!.pokemon.effects.boosts, {
            'atk': 2,
          });
        }
        expect(own(s).boosts, {'atk': 2});
      },
    );
  }
  test('Baton Pass transfers only reviewed copyable effects; Shed Tail only substitute', () {
    var s = feed(ready(), '|-boost|p1a: A|atk|2');
    for (final e in persistentEffects) {
      s = feed(s, '|-start|p1a: A|$e${e == 'disable' ? '|Tackle' : ''}');
    }
    s = feed(
      s,
      '|-singleturn|p1a: A|Protect\n|-singlemove|p1a: A|Destiny Bond',
    );
    final passed = feed(
      s,
      '|switch|p1a: C|Snorlax|100/100|[from] move: Baton Pass',
    );
    expect(own(passed).boosts, {'atk': 2});
    expect(own(passed).volatiles.keys.toSet(), passableEffects);
    final tail = feed(
      s,
      '|switch|p1a: C|Snorlax|100/100|[from] move: Shed Tail',
    );
    expect(own(tail).boosts, isEmpty);
    expect(own(tail).volatiles, {'substitute': null});
    expect(passed.unsupported, isFalse);
    expect(tail.unsupported, isFalse);
    expect(own(s).volatiles.length, 10);
  });
  test('transfer is never inferred from prior move or stale appearance', () {
    final s = feed(
      ready(),
      '|-boost|p1a: A|atk|2\n|move|p1a: A|Baton Pass|p1a: A',
    );
    expect(own(feed(s, '|switch|p1a: C|Snorlax|100/100')).boosts, isEmpty);
    expect(
      feed(
        s,
        '|drag|p1a: C|Snorlax|100/100|[from] move: Baton Pass',
      ).unsupported,
      isTrue,
    );
    final faint = feed(s, '|faint|p1a: A');
    expect(
      feed(
        faint,
        '|switch|p1a: C|Snorlax|100/100|[from] move: Baton Pass',
      ).unsupported,
      isTrue,
    );
  });
  test('invalid operations block atomically, no silent partial projection', () {
    final s = feed(ready(), '|-boost|p1a: A|atk|2');
    for (final wire in [
      '|-boost|p1a: A|hp|1',
      '|-setboost|p1a: A|atk|7',
      '|-boost|p1a: A|atk|-1',
      '|-boost|p1a: A|atk|1.5',
      '|-boost|p1a: A|atk|1|extra',
      '|-swapboost|p1a: A|p2a: Missing',
      '|-copyboost|p1a: A|p2a: B|atk, hp',
      '|-swapboost|p1a: A|p2a: B|atk,atk',
      '|-copyboost|p1a: A|p1a: A',
      '|-boost|p1: A|atk|1',
      '|-start|p1a: A|Future Sight',
      '|-start|p1a: A|typechange|Water',
      '|-start|p1a: A|Disable',
      '|-start|p1a: A|Substitute|extra',
      '|-singleturn|p1a: A|Substitute',
      '|-singlemove|p1a: A|Glaive Rush',
      '|-end|p1a: A|Illusion',
      '|-start|p1a: A|Substitute|[silent]|extra',
      '|-clearpositiveboost|p1a: A|p2a: Missing|move: Spectral Thief',
      '|switch|p1a: C|Snorlax|100/100|[from] move: Baton Pass|[from] move: Shed Tail',
    ]) {
      final failed = feed(s, wire);
      expect(failed.unsupported, isTrue, reason: wire);
      expect(own(failed).boosts, {'atk': 2}, reason: wire);
      expect(own(failed).volatiles, isEmpty, reason: wire);
    }
  });
  test('wrong room/epoch, stale and terminal events cannot change effects', () {
    final s = ready();
    const wire = '|-boost|p1a: A|atk|2';
    expect(identical(feed(s, wire, epoch: 2), s), isTrue);
    expect(identical(feed(s, wire, id: 'battle-other'), s), isTrue);
    final stale = s.markStale();
    expect(identical(feed(stale, wire), stale), isTrue);
    final end = feed(s, '|win|Alice');
    expect(identical(feed(end, wire), end), isTrue);
  });
  test('effect collections defensively copy inputs and cannot be mutated', () {
    final boosts = {'atk': 2};
    final effects = <String, String?>{'substitute': null};
    final value = PokemonEffects(boosts: boosts, volatiles: effects);
    boosts.clear();
    effects.clear();
    expect(value.boosts, {'atk': 2});
    expect(value.volatiles, {'substitute': null});
    expect(() => value.boosts['atk'] = 3, throwsUnsupportedError);
    expect(() => value.volatiles.clear(), throwsUnsupportedError);
  });
}
