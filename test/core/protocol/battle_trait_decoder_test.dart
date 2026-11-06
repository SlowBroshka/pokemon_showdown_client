import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';
import 'package:pokemon_showdown_client/core/battle/state/effect_observation.dart';

ServerEvent? decode(String wire, {bool room = true}) => decodeServerRecord(
  parseServerMessage('${room ? '>battle-test\n' : ''}$wire').single,
);
void main() {
  test(
    'typed traits distinguish operations and preserve explicit old ability',
    () {
      final events = {
        '|-item|p1a: A|Air Balloon': TraitOperation.item,
        '|-enditem|p1a: A|Sitrus Berry|[eat]': TraitOperation.endItem,
        '|-ability|p1a: A|Pressure|Trace|[from] ability: Trace|[of] p2a: B':
            TraitOperation.ability,
        '|-endability|p1a: A': TraitOperation.suppressAbility,
        '|-activate|p1a: A|Skill Swap|Pressure|Levitate|[of] p2a: B':
            TraitOperation.skillSwap,
        '|-block|p1a: A|item: Ability Shield': TraitOperation.block,
        '|-immune|p1a: A|[from] ability: Good as Gold': TraitOperation.notice,
      };
      for (final e in events.entries) {
        expect((decode(e.key) as BattleTraitEvent).operation, e.value);
      }
      final changed = decode(events.keys.elementAt(2)) as BattleTraitEvent;
      expect(changed.previous, 'Trace');
      expect(changed.other, 'p2a: B');
    },
  );
  test(
    'source wrapper retains immutable typed payload and public source metadata',
    () {
      final event = decode(
        '|-damage|p1a: A|40/100|[from] item: Rocky Helmet|[of] p2a: B',
      ) as BattleAttributedEvent;
      expect(event.inner, isA<BattleHealthEvent>());
      expect((event.inner as BattleHealthEvent).changes.single.health.hp, 40);
      expect(event.source.kind, EffectSourceKind.item);
      expect(event.source.name, 'Rocky Helmet');
      expect(event.source.ofIdent, 'p2a: B');
      expect(event.roomId, event.inner.roomId);
    },
  );
  test('malformed trait fields and duplicate flags never expose input in diagnostics', () {
    for (final wire in [
      '|-item|p1a: A|<private-secret>',
      '|-ability|p1a: A|',
      '|-enditem|p1a: A|Sitrus Berry|[eat]|[eat]',
      '|-enditem|p1a: A|Sitrus Berry|[eat]|[weaken]',
      '|-item|p1a: A|Leftovers|[from] ability: Harvest|[silent]|extra',
      '|-item|p1a: A|Leftovers|[of] p3a: B',
      '|-item|p1a: A|Leftovers|[from] move: Covet',
      '|-ability|p1a: A|Pressure|Levitate',
      '|-endability|p1a: A|Pressure',
      '|-damage|p1a: A|20/100|[from] item: Leftovers|[of] p2a: B|[of] p2a: B',
    ]) {
      final e = decode(wire);
      expect(e, isA<MalformedServerEvent>(), reason: wire);
      expect(
        (e as MalformedServerEvent).reason,
        isNot(contains('private-secret')),
      );
    }
  });
  test('scope and existing activation decoder ownership remain explicit', () {
    expect(
      decode('|-item|p1a: A|Air Balloon', room: false),
      isA<MalformedServerEvent>(),
    );
    expect(
      decode('|-activate|p1a: A|move: Court Change'),
      isA<BattleEnvironmentEvent>(),
    );
    expect(
      decode('|-activate|p1a: A|ability: Cud Chew'),
      isA<UnknownServerEvent>(),
    );
    expect(
      decode('|-activate|p1a: A|ability: FutureAbility'),
      isA<UnknownServerEvent>(),
    );
    expect(decode('|-immune|p1a: A'), isA<UnknownServerEvent>());
  });
}
