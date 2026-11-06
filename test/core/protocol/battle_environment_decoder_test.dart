import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

ServerEvent? decode(String wire, {bool room = true}) {
  final event = decodeServerRecord(
    parseServerMessage('${room ? '>battle-environment\n' : ''}$wire').single,
  );
  return event is BattleAttributedEvent ? event.inner : event;
}

void main() {
  test(
    'decodes all environment operations with normalized IDs and public sources',
    () {
      final examples = {
        '|-weather|RainDance|[from] ability: Drizzle|[of] p2a: B':
            EnvironmentOperation.weather,
        '|-fieldstart|move: Grassy Terrain': EnvironmentOperation.fieldStart,
        '|-fieldend|Misty Terrain': EnvironmentOperation.fieldEnd,
        '|-fieldactivate|move: Perish Song': EnvironmentOperation.fieldActivate,
        '|-sidestart|p1: Player|move: Toxic Spikes':
            EnvironmentOperation.sideStart,
        '|-sideend|p2: Player|Reflect|[from] move: Defog|[of] p1a: A':
            EnvironmentOperation.sideEnd,
        '|-swapsideconditions': EnvironmentOperation.swapSides,
        '|-activate|p1a: A|move: Court Change':
            EnvironmentOperation.courtChangeActivation,
      };
      for (final e in examples.entries) {
        expect(decode(e.key), isA<BattleEnvironmentEvent>(), reason: e.key);
        expect((decode(e.key) as BattleEnvironmentEvent).operation, e.value);
      }
      final weather = decode(examples.keys.first) as BattleEnvironmentEvent;
      expect(weather.condition, 'raindance');
      expect(weather.sourceEffect, 'ability: Drizzle');
      expect(weather.sourceIdent, 'p2a: B');
      expect(weather.upkeep, isFalse);
      expect(
        (decode(
          '|-weather|RainDance|[upkeep]',
        ) as BattleEnvironmentEvent).upkeep,
        isTrue,
      );
      expect(
        (decode(
          '|-sidestart|p2: Name|Spikes',
        ) as BattleEnvironmentEvent).sideId,
        'p2',
      );
    },
  );
  test('missing/excess arguments and invalid annotations yield malformed, not exceptions', () {
    for (final line in [
      '|-weather',
      '|-weather|',
      '|-weather|RainDance|none',
      '|-fieldstart',
      '|-fieldend|',
      '|-fieldactivate|',
      '|-sidestart|p1',
      '|-sideend|p1|Spikes|extra',
      '|-swapsideconditions|',
      '|-swapsideconditions|[silent]',
      '|-weather|RainDance|[of] p1a: A|[of] p1a: A',
      '|-weather|RainDance|[silent]|[silent]',
      '|-weather|RainDance|[from] item: Damp Rock',
      '|-fieldstart|move: Trick Room|[of] p1b: A',
      '|-activate|p1a: A|move: Court Change|[unexpected]',
    ]) {
      // Empty data after the separator is the canonical no-argument form.
      if (line == '|-swapsideconditions|') {
        expect(decode(line), isA<BattleEnvironmentEvent>());
      } else {
        expect(decode(line), isA<MalformedServerEvent>(), reason: line);
      }
    }
  });
  test(
    'environment is room-scoped; unrelated activate types remain unknown',
    () {
      expect(
        decode('|-weather|RainDance', room: false),
        isA<MalformedServerEvent>(),
      );
      expect(
        decode('|-swapsideconditions', room: false),
        isA<MalformedServerEvent>(),
      );
      expect(
        decode('|-activate|p1a: A|move: Court Change', room: false),
        isA<MalformedServerEvent>(),
      );
      expect(
        decode('|-activate|p1a: A|ability: Levitate'),
        isA<UnknownServerEvent>(),
      );
      expect(
        decode('|-fieldactivate|move: Fairy Lock'),
        isA<MalformedServerEvent>(),
      );
    },
  );
}
