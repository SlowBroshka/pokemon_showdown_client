import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

ServerEvent decode(String line) =>
    decodeServerRecord(parseServerMessage('>battle-test\n$line').single)!;

void main() {
  test('all supported event families are typed', () {
    final examples = <String, Type>{
      '|player|p1|A|1|1200': BattlePlayerEvent,
      '|teamsize|p1|6': BattleMetadataEvent,
      '|gen|9': BattleMetadataEvent,
      '|gametype|singles': BattleMetadataEvent,
      '|tier|[Gen 9] Random Battle': BattleMetadataEvent,
      '|start': BattleStartEvent,
      '|turn|1': BattleTurnEvent,
      '|switch|p1a: A|Pikachu|100/100': BattleSwitchEvent,
      '|drag|p2a: B|Ditto|100/100': BattleSwitchEvent,
      '|move|p1a: A|Protect|': BattleActionEvent,
      '|cant|p1a: A|slp': BattleActionEvent,
      '|-damage|p1a: A|50/100 brn|[from] brn': BattleHealthEvent,
      '|-heal|p1a: A|60/100': BattleHealthEvent,
      '|-sethp|p1a: A|30/100|p2a: B|30/100': BattleHealthEvent,
      '|-status|p1a: A|par': BattleStatusEvent,
      '|-curestatus|p1a: A|par': BattleStatusEvent,
      '|faint|p1a: A': BattleFaintEvent,
      '|-terastallize|p1a: A|Electric': BattleTeraEvent,
      '|win|A': BattleEndEvent,
      '|tie': BattleEndEvent,
    };
    for (final entry in examples.entries) {
      final event = decode(entry.key);
      expect(event.runtimeType, entry.value, reason: entry.key);
      expect(event.roomId, 'battle-test');
      expect(event.record.rawLine, entry.key);
    }
  });

  test('malformed fields never throw or expose payload in diagnostics', () {
    for (final line in [
      '|turn|-1',
      '|gen|abc',
      '|player|p9|private-secret',
      '|start|extra',
      '|tie|extra',
      '|win|',
      '|switch|p1a: A||100/100',
      '|-damage|p1a: A|101/100',
      '|-heal|p1a: A|10/0',
      '|-sethp|p1a: A|10/100|p2a: B',
      '|-status|p1a: A|future',
      '|faint|bad-ident',
      '|move|p1a: A||p2a: B',
      '|-terastallize|p1a: A|',
      '|cant|p1a: A|slp|Move|extra',
    ]) {
      final event = decode(line) as MalformedServerEvent;
      expect(event.reason, 'Invalid battle event');
      expect(event.toString(), isNot(contains('private-secret')));
    }
    expect(
      decodeServerRecord(parseServerMessage('|turn|1').single),
      isA<MalformedServerEvent>(),
    );
  });

  test(
    'annotations and two-target health updates preserve order and immutability',
    () {
      final event = decode(
        '|-sethp|p1a: A|20/100|p2a: B|40/100|[from] move: Pain Split',
      ) as BattleHealthEvent;
      expect(event.changes.map((c) => c.health.hp), [20, 40]);
      expect(() => event.changes.clear(), throwsUnsupportedError);
      final move = decode(
        '|move|p1a: A|Thunderbolt|p2a: B|[from] ability: X',
      ) as BattleActionEvent;
      expect(move.action, 'Thunderbolt');
      expect(move.target, 'p2a: B');
    },
  );

  test('malformed battle event does not stop following records', () {
    final events = parseServerMessage(
      '>battle-test\n|turn|bad\n|turn|2\n|future|x',
    ).map(decodeServerRecord).toList();
    expect(events[0], isA<MalformedServerEvent>());
    expect((events[1] as BattleTurnEvent).turn, 2);
    expect(events[2], isA<UnknownServerEvent>());
  });
}
