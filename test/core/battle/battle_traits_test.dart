import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/state/battle_reducer.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

const room = 'battle-traits';
BattleState feed(
  BattleState s,
  String wire, {
  int epoch = 1,
  String id = room,
}) {
  for (final r in parseServerMessage('>$id\n$wire')) {
    final e = decodeServerRecord(r);
    if (e != null) s = reduceBattleEvent(s, e, connectionEpoch: epoch);
  }
  return s;
}

BattleState ready() => feed(
  BattleState(roomId: room, connectionEpoch: 1),
  '|init|battle\n|gen|9\n|gametype|singles\n|start\n|turn|1\n'
  '|switch|p1a: Alpha|Pikachu, L80|100/100\n|switch|p2a: Gamma|Snorlax, L80|100/100',
);
PokemonTraits own(BattleState s) => s.active['p1']!.traits;
PokemonTraits foe(BattleState s) => s.active['p2']!.traits;

void main() {
  test('unknown, held, consumed and restored item stay distinct; healing cannot resurrect berry', () {
    final initial = ready();
    var s = feed(
      initial,
      '|-item|p1a: Alpha|Sitrus Berry\n|-enditem|p1a: Alpha|Sitrus Berry|[eat]',
    );
    expect(own(initial).itemKnowledge, ItemKnowledge.unknown);
    expect(own(s).itemKnowledge, ItemKnowledge.absent);
    expect(own(s).item, isNull);
    expect(own(s).lastEndedItem, 'Sitrus Berry');
    expect(own(s).itemEndReason, ItemEndReason.consumed);
    s = feed(s, '|-heal|p1a: Alpha|100/100|[from] item: Sitrus Berry');
    expect(own(s).itemKnowledge, ItemKnowledge.absent);
    expect(s.effectObservations.last.effect.name, 'Sitrus Berry');
    expect(s.effectObservations.last.sourceAppearanceId, 1);
    s = feed(s, '|-item|p1a: Alpha|Sitrus Berry|[from] ability: Harvest');
    expect(own(s).item, 'Sitrus Berry');
    expect(s.unsupported, isFalse);
  });
  for (final reason in {
    '[eat]': ItemEndReason.consumed,
    '[weaken]': ItemEndReason.consumed,
    '[from] move: Knock Off|[of] p2a: Gamma': ItemEndReason.removed,
    '[silent]|[from] move: Trick': ItemEndReason.transferred,
    '': ItemEndReason.ended,
  }.entries) {
    test('item ending ${reason.key} has explicit reason', () {
      final s = feed(
        ready(),
        '|-enditem|p1a: Alpha|Sitrus Berry${reason.key.isEmpty ? '' : '|${reason.key}'}',
      );
      expect(own(s).itemEndReason, reason.value);
      expect(own(s).itemKnowledge, ItemKnowledge.absent);
      expect(s.unsupported, isFalse);
    });
  }
  for (final source in [
    'move: Covet',
    'move: Thief',
    'move: Bestow',
    'ability: Magician',
    'ability: Pickpocket',
  ]) {
    test('$source transfers without stale donor inventory', () {
      final start = feed(ready(), '|-item|p2a: Gamma|Leftovers');
      final s = feed(
        start,
        '|-item|p1a: Alpha|Leftovers|[from] $source|[of] p2a: Gamma',
      );
      expect(own(s).item, 'Leftovers');
      expect(foe(s).itemKnowledge, ItemKnowledge.absent);
      expect(foe(s).itemEndReason, ItemEndReason.transferred);
      expect(foe(start).item, 'Leftovers');
      expect(s.unsupported, isFalse);
      if (source == 'ability: Magician') {
        expect(s.effectObservations.last.sourceAppearanceId, 1);
      }
    });
  }
  test('Frisk reveals the target item and attributes ability to the other appearance', () {
    final s = feed(
      ready(),
      '|-item|p2a: Gamma|Leftovers\n|-item|p1a: Alpha|Choice Scarf|[from] ability: Frisk|[of] p2a: Gamma',
    );
    expect(own(s).item, 'Choice Scarf');
    expect(foe(s).item, 'Leftovers');
    expect(s.effectObservations.last.sourceAppearanceId, 2);
    expect(s.effectObservations.last.targetAppearanceId, 1);
  });
  test('Trick and Switcheroo use explicit assignments, not guessed swaps', () {
    var s = feed(
      ready(),
      '|-item|p1a: Alpha|Choice Scarf\n|-item|p2a: Gamma|Leftovers',
    );
    s = feed(s, '|-activate|p1a: Alpha|move: Trick|[of] p2a: Gamma');
    expect(own(s).item, 'Choice Scarf');
    s = feed(
      s,
      '|-item|p2a: Gamma|Choice Scarf|[from] move: Trick\n|-item|p1a: Alpha|Leftovers|[from] move: Trick',
    );
    expect(own(s).item, 'Leftovers');
    expect(foe(s).item, 'Choice Scarf');
    s = feed(
      s,
      '|-enditem|p1a: Alpha|Leftovers|[from] move: Knock Off|[of] p2a: Gamma\n|-activate|p1a: Alpha|move: Switcheroo|[of] p2a: Gamma\n|-enditem|p2a: Gamma|Choice Scarf|[silent]|[from] move: Switcheroo\n|-item|p1a: Alpha|Choice Scarf|[from] move: Switcheroo',
    );
    expect(own(s).item, 'Choice Scarf');
    expect(foe(s).itemKnowledge, ItemKnowledge.absent);
    expect(s.unsupported, isFalse);
  });
  test('Bug Bite consumes donor berry without assigning it to the eater', () {
    final s = feed(
      ready(),
      '|-item|p1a: Alpha|Sitrus Berry\n|-enditem|p1a: Alpha|Sitrus Berry|[from] stealeat|[move] Bug Bite|[of] p2a: Gamma',
    );
    expect(own(s).itemKnowledge, ItemKnowledge.absent);
    expect(own(s).itemEndReason, ItemEndReason.consumed);
    expect(foe(s).itemKnowledge, ItemKnowledge.unknown);
    expect(s.unsupported, isFalse);
  });
  test('recovery sources restore only named appearance', () {
    for (final source in [
      'move: Recycle',
      'ability: Pickup',
      'ability: Harvest',
    ]) {
      final s = feed(
        ready(),
        '|-enditem|p1a: Alpha|Sitrus Berry|[eat]\n|-item|p1a: Alpha|Sitrus Berry|[from] $source',
      );
      expect(own(s).item, 'Sitrus Berry');
      expect(foe(s).itemKnowledge, ItemKnowledge.unknown);
      expect(s.unsupported, isFalse);
    }
  });
  test('ability reveal, change and explicit suppression are independent', () {
    var s = feed(ready(), '|-ability|p1a: Alpha|Intimidate|boost');
    expect(own(s).ability, 'Intimidate');
    expect(own(s).previousAbility, isNull);
    s = feed(
      s,
      '|-ability|p1a: Alpha|Insomnia|Intimidate|[from] move: Worry Seed|[of] p2a: Gamma',
    );
    expect(own(s).ability, 'Insomnia');
    expect(own(s).previousAbility, 'Intimidate');
    s = feed(
      s,
      '|-endability|p1a: Alpha\n|-ability|p1a: Alpha|Pressure|Insomnia|[from] move: Role Play|[of] p2a: Gamma',
    );
    expect(own(s).suppressed, isTrue);
    expect(own(s).ability, 'Pressure');
    expect(s.unsupported, isFalse);
  });
  test('Trace relation denotes copied Pokemon; Trace owner remains actor', () {
    final s = feed(
      ready(),
      '|-ability|p1a: Alpha|Pressure|Trace|[from] ability: Trace|[of] p2a: Gamma',
    );
    expect(own(s).ability, 'Pressure');
    expect(own(s).previousAbility, 'Trace');
    expect(s.effectObservations.last.sourceAppearanceId, 1);
    expect(s.effectObservations.last.effect.ofIdent, 'p2a: Gamma');
  });
  test(
    'Skill Swap atomically applies server-named abilities in recipient order',
    () {
      final s = feed(
        ready(),
        '|-activate|p1a: Alpha|Skill Swap|Pressure|Levitate|[of] p2a: Gamma',
      );
      expect(own(s).ability, 'Pressure');
      expect(own(s).previousAbility, 'Levitate');
      expect(foe(s).ability, 'Levitate');
      expect(foe(s).previousAbility, 'Pressure');
      expect(s.unsupported, isFalse);
    },
  );
  test('ability/item notifications and blocks are evidence, not persistent assignments', () {
    var s = feed(
      ready(),
      '|-activate|p1a: Alpha|ability: Toxic Debris\n|-activate|p1a: Alpha|item: Quick Claw\n|-block|p1a: Alpha|item: Ability Shield\n|-block|p1a: Alpha|ability: Aroma Veil|[of] p2a: Gamma\n|-immune|p1a: Alpha|[from] ability: Good as Gold',
    );
    expect(own(s).ability, isNull);
    expect(own(s).itemKnowledge, ItemKnowledge.unknown);
    expect(s.effectObservations.map((e) => e.effect.name), [
      'Toxic Debris',
      'Quick Claw',
      'Ability Shield',
      'Aroma Veil',
      'Good as Gold',
    ]);
    expect(s.effectObservations[3].sourceAppearanceId, 2);
    expect(s.unsupported, isFalse);
    s = feed(
      s,
      '|-start|p1a: Alpha|Substitute\n|-activate|p1a: Alpha|move: Substitute|[damage]',
    );
    expect(s.active['p1']!.effects.volatiles, {'substitute': null});
    expect(s.unsupported, isFalse);
  });
  test('attributed damage and boost keep source/target separate and do not infer holdings', () {
    final s = feed(
      ready(),
      '|-damage|p1a: Alpha|90/100|[from] item: Rocky Helmet|[of] p2a: Gamma\n|-unboost|p1a: Alpha|atk|1|[from] ability: Intimidate|[of] p2a: Gamma',
    );
    expect(s.active['p1']!.health.hp, 90);
    expect(s.active['p1']!.effects.boosts, {'atk': -1});
    expect(s.effectObservations.map((e) => e.sourceAppearanceId), [2, 2]);
    expect(s.effectObservations.map((e) => e.targetAppearanceId), [1, 1]);
    expect(foe(s).itemKnowledge, ItemKnowledge.unknown);
    expect(s.unsupported, isFalse);
  });
  test('weather source and ending source survive as observations without hidden ability inference', () {
    final s = feed(
      ready(),
      '|-weather|RainDance|[from] ability: Drizzle|[of] p2a: Gamma\n|-sidestart|p1|Spikes\n|-sideend|p1|Spikes|[from] move: Defog|[of] p2a: Gamma',
    );
    expect(s.effectObservations.first.sourceAppearanceId, 2);
    expect(s.effectObservations.last.sourceAppearanceId, 2);
    expect(foe(s).ability, isNull);
    expect(s.unsupported, isFalse);
  });
  test('switch clears current knowledge but retains historical appearance and source links', () {
    final s = feed(
      ready(),
      '|-item|p1a: Alpha|Leftovers\n|-ability|p1a: Alpha|Pressure',
    );
    final next = feed(
      s,
      '|switch|p1a: Beta|Snorlax|100/100\n|switch|p1a: Alpha|Pikachu|100/100',
    );
    expect(own(next).itemKnowledge, ItemKnowledge.unknown);
    expect(own(next).ability, isNull);
    expect(next.roster.appearances[1]!.pokemon.traits.item, 'Leftovers');
    expect(next.effectObservations.first.targetAppearanceId, 1);
  });
  test('HP/status/Tera/faint preserve public traits; uncertain suppression transfer blocks', () {
    var s = feed(
      ready(),
      '|-item|p1a: Alpha|Leftovers\n|-ability|p1a: Alpha|Pressure\n|-damage|p1a: Alpha|90/100\n|-status|p1a: Alpha|par\n|-terastallize|p1a: Alpha|Electric',
    );
    expect(own(s).item, 'Leftovers');
    expect(own(s).ability, 'Pressure');
    final faint = feed(s, '|faint|p1a: Alpha');
    expect(own(faint).item, 'Leftovers');
    s = feed(s, '|-endability|p1a: Alpha');
    expect(
      feed(
        s,
        '|switch|p1a: Beta|Snorlax|100/100|[from] move: Baton Pass',
      ).unsupported,
      isTrue,
    );
    expect(
      own(feed(s, '|switch|p1a: Beta|Snorlax|100/100')).suppressed,
      isFalse,
    );
  });
  test('private request does not populate public item/ability knowledge', () {
    final data = jsonDecode(
      File('test/fixtures/battle/requests.json').readAsStringSync(),
    ) as Map;
    final payload = (data['cases'] as List).firstWhere(
      (e) => e['id'] == 'move',
    )['payload'];
    final s = feed(ready(), '|request|${jsonEncode(payload)}');
    expect(own(s).itemKnowledge, ItemKnowledge.unknown);
    expect(own(s).ability, isNull);
    expect(s.effectObservations, isEmpty);
  });
  test('bad actor, donor, names, counts, flags and unsupported semantic subtypes block atomically', () {
    final s = feed(
      ready(),
      '|-item|p1a: Alpha|Leftovers\n|-ability|p1a: Alpha|Pressure',
    );
    for (final wire in [
      '|-item|p1a: Missing|Air Balloon',
      '|-item|p1: Alpha|Air Balloon',
      '|-item|p1a: Alpha|Leftovers|[from] move: Covet|[of] p2a: Missing',
      '|-item|p1a: Alpha|Leftovers|[from] move: Covet|[of] p1a: Alpha',
      '|-item|p1a: Alpha|Leftovers|[from] ability: FutureAbility',
      '|-item|p1a: Alpha||[silent]',
      '|-item|p1a: Alpha|Leftovers|extra',
      '|-enditem|p1a: Alpha|Sitrus Berry|[eat]',
      '|-ability|p1a: Alpha|Neutralizing Gas',
      '|-ability|p1a: Alpha|As One',
      '|-ability|p1a: Alpha|Pressure|boost',
      '|-endability|p1a: Alpha|Pressure',
      '|-activate|p1a: Alpha|Skill Swap|Pressure|Levitate|[of] p2a: Missing',
      '|-activate|p1a: Alpha|Skill Swap|||[of] p2a: Gamma',
      '|-activate|p1a: Alpha|ability: Commander|[of] p2a: Gamma',
      '|-activate|p1a: Alpha|move: Substitute|[damage]',
      '|-block|p1a: Alpha|ability: Good as Gold|Thunder Wave|p2a: Gamma',
      '|-damage|p1a: Alpha|50/100|[from] item: Rocky Helmet|[of] p2a: Missing',
      '|-damage|p1a: Alpha|50/100|[from] item: Leftovers|[from] item: Rocky Helmet',
      '|-damage|p1a: Alpha|500/100|[from] item: Rocky Helmet|[of] p2a: Gamma',
    ]) {
      final bad = feed(s, wire);
      expect(bad.unsupported, isTrue, reason: wire);
      expect(identical(bad.roster, s.roster), isTrue, reason: wire);
      expect(bad.effectObservations, s.effectObservations, reason: wire);
    }
  });
  test('observations bounded and immutable; stale/terminal/wrong room cannot change traits', () {
    var s = ready();
    for (var i = 0; i < maxEffectObservations + 2; i++) {
      s = feed(s, '|-activate|p1a: Alpha|item: Quick Claw');
    }
    expect(s.effectObservations.length, maxEffectObservations);
    expect(() => s.effectObservations.clear(), throwsUnsupportedError);
    const wire = '|-item|p1a: Alpha|Air Balloon';
    expect(identical(feed(s, wire, epoch: 2), s), isTrue);
    expect(identical(feed(s, wire, id: 'battle-other'), s), isTrue);
    for (final state in [s.markStale(), feed(s, '|win|Alice')]) {
      expect(identical(feed(state, wire), state), isTrue);
    }
  });
}
