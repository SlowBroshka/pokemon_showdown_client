import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

ServerEvent? decode(String message) =>
    decodeServerRecord(parseServerMessage(message).single);

void main() {
  group('decodeServerRecord', () {
    test('preserves complete challenge and original record', () {
      final record = parseServerMessage('|challstr|4|secret|tail').single;
      final event = decodeServerRecord(record) as ChallengeEvent;
      expect(event.challenge, '4|secret|tail');
      expect(event.record, same(record));
      expect(event.roomId, isNull);
      expect(event.toString(), isNot(contains('secret')));
    });

    test('decodes updateuser with a JSON tail containing pipes', () {
      final event = decode(
        '|updateuser| Alice@!|1|custom-avatar|{"text":"a|b"}',
      ) as UpdateUserEvent;
      expect(event.user, ' Alice@!');
      expect(event.named, isTrue);
      expect(event.avatar, 'custom-avatar');
      expect(event.settingsJson, '{"text":"a|b"}');
    });

    test('accepts legacy updateuser without settings and guest flag', () {
      final event = decode('|updateuser| Guest 1|0|1') as UpdateUserEvent;
      expect(event.named, isFalse);
      expect(event.settingsJson, isNull);
      expect(event.avatar, '1');
    });

    test('decodes room lifecycle preserving context and title', () {
      final events = parseServerMessage(
        '>battle-test\n|init|battle\n|title| Alice | Bob \n|deinit',
      ).map(decodeServerRecord).toList();
      expect((events[0] as RoomInitEvent).roomType, 'battle');
      expect((events[1] as RoomTitleEvent).title, ' Alice | Bob ');
      expect(events[2], isA<RoomDeinitEvent>());
      expect(events.map((event) => event!.roomId), everyElement('battle-test'));
      expect((decode('|init|chat') as RoomInitEvent).roomId, isNull);
      expect((decode('|init|future') as RoomInitEvent).roomType, 'future');
      expect(decode('|deinit|'), isA<RoomDeinitEvent>());
    });

    test('preserves error, popup and name rejection text', () {
      expect(
        (decode('|error| Ошибка | детали ') as ServerErrorEvent).message,
        ' Ошибка | детали ',
      );
      expect(
        (decode('|popup|One||Two|Three') as PopupEvent).message,
        'One||Two|Three',
      );
      final rejected =
          decode('|nametaken|Alice| Already | taken ') as NameTakenEvent;
      expect(rejected.username, 'Alice');
      expect(rejected.message, ' Already | taken ');
      final invalidName = decode('|nametaken||Invalid name') as NameTakenEvent;
      expect(invalidName.username, '');
      expect(invalidName.message, 'Invalid name');
      expect((decode('|error|') as ServerErrorEvent).message, '');
      expect((decode('|popup|') as PopupEvent).message, '');
    });

    test(
      'normalizes plain text and empty-name events but skips empty lines',
      () {
        expect(
          (decode(' hello | мир ') as PlainTextEvent).text,
          ' hello | мир ',
        );
        expect(
          (decode('|| hello | мир ') as PlainTextEvent).text,
          ' hello | мир ',
        );
        expect((decode('|') as PlainTextEvent).text, '');
        expect(decode('\n'), isNull);
        expect(decode('>battle-test\n\n'), isNull);
      },
    );

    test('leaves unknown, battle and HTML events uninterpreted', () {
      for (final type in ['future', 'move', 'html', 'uhtml']) {
        final event =
            decode('>battle-test\n|$type|<b>x</b>|{}') as UnknownServerEvent;
        expect(event.eventType, type);
        expect(event.data, '<b>x</b>|{}');
        expect(event.roomId, 'battle-test');
      }
    });

    test('returns malformed for invalid supported events without throwing', () {
      for (final line in [
        '>',
        '|challstr|',
        '|updateuser|',
        '|updateuser||1|1',
        '|updateuser|Alice|1',
        '|updateuser|Alice|true|1',
        '|updateuser|Alice|2|1',
        '|updateuser|Alice|1|',
        '|updateuser|Alice|1|1|',
        '|updateuser|Alice|1|1|not json',
        '|updateuser|Alice|1|1|[]',
        '|updateuser|Alice|1|1|null',
        '|updateuser|Alice|1|1|{"ok":true}|extra',
        '|init|',
        '|init|chat|extra',
        '|title|',
        '|deinit|extra',
        '|nametaken|Alice',
        '|nametaken|Alice|',
      ]) {
        expect(decode(line), isA<MalformedServerEvent>(), reason: line);
      }
    });

    test('handles manually constructed records with missing event fields', () {
      for (final record in [
        const ServerRecord(
          roomId: null,
          rawLine: '|x',
          kind: ServerRecordKind.event,
        ),
        const ServerRecord(
          roomId: null,
          rawLine: '|x',
          kind: ServerRecordKind.event,
          eventType: 'x',
        ),
      ]) {
        expect(decodeServerRecord(record), isA<MalformedServerEvent>());
      }
    });

    test('malformed data does not leak into reason or stop the next record', () {
      final events = parseServerMessage(
        '>battle-test\n|updateuser|private-secret\n|title|Next\n\n|future|data',
      ).map(decodeServerRecord).toList();
      final failure = events.first as MalformedServerEvent;
      expect(failure.roomId, 'battle-test');
      expect(failure.reason, isNot(contains('private-secret')));
      expect(failure.toString(), isNot(contains('private-secret')));
      expect(failure.record.data, 'private-secret');
      expect(events[1], isA<RoomTitleEvent>());
      expect(events[2], isNull);
      expect(events[3], isA<UnknownServerEvent>());
    });
  });
}
