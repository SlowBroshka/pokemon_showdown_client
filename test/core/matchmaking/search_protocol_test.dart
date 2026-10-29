import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/matchmaking/search/search_snapshot.dart';
import 'package:pokemon_showdown_client/core/matchmaking/search/search_snapshot_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/client_commands.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

void main() {
  final corpus = jsonDecode(
    File('test/fixtures/matchmaking/messages.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final c in (corpus['cases'] as List).cast<Map<String, dynamic>>().where(
    (c) => c['kind'] == 'updatesearch',
  )) {
    test('updatesearch corpus: ${c['id']}', () {
      final event = decodeServerRecord(
        parseServerMessage(c['wire'] as String).single,
      );
      final expected = c['expect'] as Map<String, dynamic>;
      if (expected['classification'] == 'wrongScope') {
        expect(event, isA<MalformedServerEvent>());
        return;
      }
      expect(event, isA<UpdateSearchEvent>());
      final result = (event as UpdateSearchEvent).result;
      expect(result.isValid, expected['classification'] == 'valid');
      if (result.isValid) {
        expect(result.snapshot!.searching, expected['searching']);
        expect(result.snapshot!.games, expected['games']);
      } else {
        expect(result.snapshot, isNull);
      }
    });
  }

  test('snapshots defensively copy collections and expose immutable views', () {
    final searching = ['gen9randombattle'];
    final games = {'battle-example': 'Title'};
    final snapshot = SearchSnapshot(searching: searching, games: games);
    searching.clear();
    games.clear();
    expect(snapshot.searching, ['gen9randombattle']);
    expect(snapshot.games, {'battle-example': 'Title'});
    expect(() => snapshot.searching.add('gen9ou'), throwsUnsupportedError);
    expect(() => snapshot.games!['mafia'] = 'Changed', throwsUnsupportedError);
  });

  test(
    'preserves external searches, non-battle games and untrusted titles',
    () {
      final result = decodeSearchSnapshot(
        jsonEncode({
          'searching': ['gen9ou', 'gen9randombattle'],
          'games': {
            'mafia': '<b>Example</b>|/search gen9ou\n*',
            'battle-example': '',
          },
          'future': {'anything': true},
        }),
      );
      expect(result.snapshot!.searching, ['gen9ou', 'gen9randombattle']);
      expect(
        result.snapshot!.games!['mafia'],
        '<b>Example</b>|/search gen9ou\n*',
      );
      expect(result.snapshot!.games!['battle-example'], '');
    },
  );

  test('null and empty games are valid but distinct; invalid is neither', () {
    expect(
      decodeSearchSnapshot('{"searching":[],"games":null}').snapshot!.games,
      isNull,
    );
    expect(
      decodeSearchSnapshot('{"searching":[],"games":{}}').snapshot!.games,
      isEmpty,
    );
    expect(decodeSearchSnapshot('{"searching":[]}').snapshot, isNull);
    expect(decodeSearchSnapshot('{"searching":[]}').isValid, isFalse);
  });

  test('rejects missing fields and wrong JSON types without coercion', () {
    for (final raw in [
      '',
      'null',
      '[]',
      'true',
      '1',
      '"text"',
      '{}',
      '{"games":null}',
      '{"searching":null,"games":null}',
      '{"searching":[1],"games":null}',
      '{"searching":[],"games":false}',
      '{"searching":[],"games":{"mafia":null}}',
    ]) {
      expect(decodeSearchSnapshot(raw).isValid, isFalse, reason: raw);
    }
  });

  test(
    'strict IDs reject empty, uppercase, whitespace and framing characters',
    () {
      for (final id in [
        '',
        'UPPER',
        'has space',
        'x|y',
        'x\ny',
        'x\ry',
        'x\u0000y',
        'x\u0085y',
        'x\u2028y',
        'покемон',
        ' x',
        'x ',
      ]) {
        expect(
          decodeSearchSnapshot(
            jsonEncode({
              'searching': [id],
              'games': null,
            }),
          ).isValid,
          isFalse,
          reason: id,
        );
        expect(
          decodeSearchSnapshot(
            jsonEncode({
              'searching': [],
              'games': {id: 'Title'},
            }),
          ).isValid,
          isFalse,
          reason: id,
        );
      }
      expect(
        decodeSearchSnapshot('{"searching":["gen9-ou"],"games":null}').isValid,
        isFalse,
      );
      expect(
        decodeSearchSnapshot(
          '{"searching":[],"games":{"groupchat-example-room":"Title"}}',
        ).isValid,
        isTrue,
      );
    },
  );

  test(
    'serializes exact global commands without an implicit send or cancel-all',
    () {
      final commands = <ClientCommand>[
        const PrepareRandomTeamCommand(),
        SearchBattleCommand(formatId: 'gen9randombattle'),
        CancelSearchCommand(formatId: 'gen9randombattle'),
      ];
      expect(commands.map((c) => c.serialize()), [
        '|/utm null',
        '|/search gen9randombattle',
        '|/cancelsearch gen9randombattle',
      ]);
      for (final command in commands) {
        expect(command.serialize(), command.serialize());
        expect(command.serialize(), isNot(contains('\n')));
      }
    },
  );

  test(
    'outgoing allowlist rejects unsupported formats and command injection',
    () {
      final inputs = [
        '',
        'gen9ou',
        'gen9unratedrandombattle',
        '[Gen 9] Random Battle',
        'GEN9RANDOMBATTLE',
        'gen9randombattle ',
        ' gen9randombattle',
        'gen9randombattle@@@custom',
        'gen9randombattle,other',
        for (var c = 0; c <= 31; c++)
          'gen9randombattle${String.fromCharCode(c)}',
        for (var c = 127; c <= 159; c++)
          'gen9randombattle${String.fromCharCode(c)}',
        'gen9randombattle|/leave',
        'gen9randombattle\u2028',
        'gen9randombattle\u2029',
      ];
      for (final id in inputs) {
        for (final build in [
          SearchBattleCommand.new,
          CancelSearchCommand.new,
        ]) {
          expect(() => build(formatId: id), throwsArgumentError);
        }
      }
    },
  );

  test('popup and error are not search acknowledgements', () {
    final events = parseServerMessage('|popup|Warning\n|error|Refusal')
        .map(decodeServerRecord)
        .toList();
    expect(events[0], isA<PopupEvent>());
    expect(events[1], isA<ServerErrorEvent>());
    expect(events.whereType<UpdateSearchEvent>(), isEmpty);
  });
}
