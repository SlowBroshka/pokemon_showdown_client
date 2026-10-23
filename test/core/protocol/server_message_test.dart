import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

void main() {
  group('parseServerMessage', () {
    test('preserves global events, text and empty lines in order', () {
      final records = parseServerMessage(
        '|updateuser|Alice|1\n hello \n\n|done',
      );

      expect(records.map((record) => record.roomId), everyElement(isNull));
      expect(records.map((record) => record.kind), [
        ServerRecordKind.event,
        ServerRecordKind.text,
        ServerRecordKind.empty,
        ServerRecordKind.event,
      ]);
      expect(records.map((record) => record.rawLine), [
        '|updateuser|Alice|1',
        ' hello ',
        '',
        '|done',
      ]);
      expect(records.first.eventType, 'updateuser');
      expect(records.first.data, 'Alice|1');
      expect(records[1].eventType, isNull);
      expect(records[1].data, isNull);
      expect(records[2].eventType, isNull);
      expect(records[2].data, isNull);
      expect(records.last.data, '');
    });

    test('room headers change context without emitting a record', () {
      final records = parseServerMessage(
        '|global\n>battle-one\n|init|battle\n|turn|1\n>battle-two\n|tie',
      );

      expect(records.map((record) => record.roomId), [
        null,
        'battle-one',
        'battle-one',
        'battle-two',
      ]);
      expect(records.map((record) => record.eventType), [
        'global',
        'init',
        'turn',
        'tie',
      ]);
      expect(parseServerMessage('>battle-only'), isEmpty);
    });

    test('each call starts in global context', () {
      parseServerMessage('>battle-one\n|turn|1');
      expect(parseServerMessage('|updateuser|Alice').single.roomId, isNull);
    });

    test('preserves pipes, spaces, Unicode and uninterpreted payloads', () {
      final payloads = {
        'c': ' Alice| Привет | мир  ',
        'challstr': '4|challenge|tail',
        'request': '{"text":"a|b", "rqid":7}',
        'future-event': ' unknown|data ',
        'html': '<script>alert("x")</script>',
      };

      for (final entry in payloads.entries) {
        final line = '|${entry.key}|${entry.value}';
        final record = parseServerMessage(line).single;
        expect(record.kind, ServerRecordKind.event);
        expect(record.eventType, entry.key);
        expect(record.data, entry.value);
        expect(record.rawLine, line);
      }
    });

    test('accepts events with absent data or empty event names', () {
      final records = parseServerMessage('|tie\n|tie|\n|\n||text');
      expect(records.map((record) => record.eventType), ['tie', 'tie', '', '']);
      expect(records.map((record) => record.data), ['', '', '', 'text']);
      expect(
        records.map((record) => record.kind),
        everyElement(ServerRecordKind.event),
      );
    });

    test('empty input and final terminators do not add phantom records', () {
      expect(parseServerMessage(''), isEmpty);
      expect(parseServerMessage('|tie\n'), hasLength(1));
      expect(parseServerMessage('|tie\r\n'), hasLength(1));
      expect(parseServerMessage('\n').single.kind, ServerRecordKind.empty);
      expect(parseServerMessage('\r\n').single.rawLine, '');
      expect(parseServerMessage('|tie\n\n'), hasLength(2));
    });

    test('handles mixed LF and CRLF without trimming data', () {
      final records = parseServerMessage('>battle-one\r\n|turn|1\n text \r\n');
      expect(records.map((record) => record.rawLine), ['|turn|1', ' text ']);
      expect(
        records.map((record) => record.roomId),
        everyElement('battle-one'),
      );
      expect(parseServerMessage('|x|a\rb\r').single.data, 'a\rb\r');
    });

    test('a bare room header emits a malformed record and resets context', () {
      final records = parseServerMessage(
        '>battle-one\n|turn|1\n>\r\n|global\n>battle-two\n|tie',
      );
      expect(records.map((record) => record.roomId), [
        'battle-one',
        null,
        null,
        'battle-two',
      ]);
      expect(records[1].kind, ServerRecordKind.malformed);
      expect(records[1].rawLine, '>');
      expect(records[1].eventType, isNull);
      expect(records[1].data, isNull);
      expect(parseServerMessage('>').single.kind, ServerRecordKind.malformed);
    });

    test('returned lists cannot be modified', () {
      final records = parseServerMessage('|tie');
      expect(() => records.clear(), throwsUnsupportedError);
      expect(() => records[0] = records[0], throwsUnsupportedError);
      expect(
        () => parseServerMessage('').add(records[0]),
        throwsUnsupportedError,
      );
    });
  });
}
