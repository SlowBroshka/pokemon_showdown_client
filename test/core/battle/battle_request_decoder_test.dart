import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/requests/battle_request_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

void main() {
  final fixtures =
      (jsonDecode(File('test/fixtures/battle/requests.json').readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List;
  Map<String, dynamic> move() => jsonDecode(
    jsonEncode(
      (fixtures.firstWhere((c) => c['id'] == 'move') as Map)['payload'],
    ),
  ) as Map<String, dynamic>;
  BattleRequest mutated(void Function(Map<String, dynamic>) mutate) {
    final input = move();
    mutate(input);
    return decodeBattleRequest(jsonEncode(input));
  }

  for (final fixture in fixtures) {
    test('contract: ${fixture['id']}', () {
      final payload = fixture.containsKey('rawPayload')
          ? fixture['rawPayload'] as String
          : jsonEncode(fixture['payload']);
      final result = decodeBattleRequest(payload);
      final expected = fixture['expect'];
      expect(result.kind.wireName, expected['kind']);
      expect(result.moveSlots, expected['moveSlots']);
      expect(result.switchSlots, expected['switchSlots']);
      expect(result.canTerastallize, expected['canTerastallize']);
      if (result.reason != null) {
        expect(result.side, isNull);
        expect(result.active, isNull);
      }
    });
  }

  test('real engine empty terastallized means not yet transformed', () {
    final result = mutated(
      (j) => j['side']['pokemon'][0]['terastallized'] = '',
    );
    expect(result.kind, BattleRequestKind.move);
    expect(result.side!.pokemon.first.terastallized, isNull);
    final invalid = mutated((j) => j['active'][0]['canTerastallize'] = '');
    expect(invalid.kind, BattleRequestKind.malformedRequest);
  });

  test('preserves private data and uses request indices, not names', () {
    final result = mutated((j) {
      j['side']['pokemon'][0]['condition'] = '123/200 par';
      j['side']['pokemon'][0]['ident'] = 'p1: Secret | Name';
      j['side']['pokemon'][0]['item'] = '';
      j['side']['pokemon'][1].remove('ability');
      j['side']['pokemon'][1]['active'] = true;
      j['side']['pokemon'][0]['active'] = false;
    });
    expect(result.kind, BattleRequestKind.move);
    expect(result.rqid, 7);
    expect(result.switchSlots, [1]);
    final pokemon = result.side!.pokemon.first;
    expect(pokemon.ident, 'p1: Secret | Name');
    expect(pokemon.condition.hp, 123);
    expect(pokemon.condition.maxHp, 200);
    expect(pokemon.condition.status, PokemonStatus.par);
    expect(pokemon.item, '');
    expect(result.side!.pokemon[1].ability, isNull);
    expect(pokemon.moves, ['thunderbolt', 'protect']);
    expect(pokemon.stats['atk'], 150);
    expect(result.active!.moves.first.name, 'Thunderbolt');
    expect(result.active!.moves.first.pp, 15);
    expect(result.active!.moves[1].disabled, isTrue);
  });

  test('p2 and all six statuses preserve private HP', () {
    for (final status in PokemonStatus.values) {
      final result = mutated((j) {
        j['side']['id'] = 'p2';
        for (final pokemon in j['side']['pokemon']) {
          pokemon['ident'] = (pokemon['ident'] as String).replaceFirst(
            'p1:',
            'p2:',
          );
        }
        j['side']['pokemon'][0]['condition'] = '1/200 ${status.name}';
        j['requestType'] = 'move';
      });
      expect(result.kind, BattleRequestKind.move);
      expect(result.side!.id, 'p2');
      expect(result.side!.pokemon.first.condition.status, status);
    }
  });

  test('revival and commanding are not ordinary replacement requests', () {
    for (final flag in ['reviving', 'commanding']) {
      final input = move();
      input.remove('active');
      input['forceSwitch'] = [true];
      input['side']['pokemon'][0][flag] = true;
      final result = decodeBattleRequest(jsonEncode(input));
      expect(result.kind, BattleRequestKind.unsupportedRequest);
      expect(result.switchSlots, isEmpty);
    }
  });

  test('same rqid still decodes an independent complete snapshot', () {
    final first = decodeBattleRequest(jsonEncode(move()));
    final second = mutated(
      (j) => j['active'][0]['moves'][0]['disabled'] = true,
    );
    expect(first.rqid, second.rqid);
    expect(first.moveSlots, [1]);
    expect(second.moveSlots, isEmpty);
    expect(identical(first, second), isFalse);
  });

  test('all returned collections are immutable', () {
    final result = decodeBattleRequest(jsonEncode(move()));
    expect(() => result.side!.pokemon.clear(), throwsUnsupportedError);
    expect(
      () => result.side!.pokemon.first.moves.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => result.side!.pokemon.first.stats.clear(),
      throwsUnsupportedError,
    );
    expect(() => result.active!.moves.clear(), throwsUnsupportedError);
    expect(() => result.moveSlots.add(4), throwsUnsupportedError);
    expect(() => result.switchSlots.clear(), throwsUnsupportedError);
  });

  test('does not coerce fields or allow inconsistent shapes', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (j) => j['rqid'] = -1,
      (j) => j['rqid'] = 7.0,
      (j) => j['rqid'] = null,
      (j) => j['noCancel'] = 'true',
      (j) => j['active'] = {},
      (j) => j['active'] = [null],
      (j) => j['side'] = [],
      (j) => j['side']['pokemon'] = [],
      (j) => j['side']['pokemon'][0]['active'] = 1,
      (j) => j['side']['pokemon'][0]['active'] = false,
      (j) => j['side']['pokemon'][1]['active'] = true,
      (j) => j['side']['pokemon'][0]['condition'] = '0 fnt',
      (j) => j['side']['pokemon'][0]['condition'] = '10/0',
      (j) => j['side']['pokemon'][0]['condition'] = '10/20 mystery',
      (j) => j['side']['pokemon'][0]['ident'] = 'p2: Secret',
      (j) => j['side']['pokemon'][0]['stats'] = {'atk': '150'},
      (j) => j['active'][0]['trapped'] = 'false',
      (j) => j['active'][0]['canTerastallize'] = true,
      (j) => j['active'][0]['moves'][0]['pp'] = 25,
      (j) => j['active'][0]['moves'][0]['maxpp'] = 0,
      (j) => j['active'][0]['moves'][0]['disabled'] = 1,
      (j) => j['active'][0]['moves'][0].remove('move'),
      (j) => j['requestType'] = 'switch',
      (j) => j['forceSwitch'] = [true],
    ];
    for (var i = 0; i < mutations.length; i++) {
      final result = mutated(mutations[i]);
      expect(
        result.kind,
        BattleRequestKind.malformedRequest,
        reason: 'mutation $i',
      );
      expect(result.moveSlots, isEmpty);
      expect(result.switchSlots, isEmpty);
    }
  });

  test('known unsupported mechanics do not fall through to move', () {
    for (final key in [
      'canMegaEvo',
      'canMegaEvoX',
      'canMegaEvoY',
      'canUltraBurst',
      'canDynamax',
    ]) {
      expect(
        mutated((j) => j['active'][0][key] = true).kind,
        BattleRequestKind.unsupportedRequest,
      );
    }
    for (final key in ['canZMove', 'zMoves', 'maxMoves']) {
      expect(
        mutated((j) => j['active'][0][key] = []).kind,
        BattleRequestKind.unsupportedRequest,
      );
    }
    expect(
      mutated((j) => j['ally'] = {}).kind,
      BattleRequestKind.unsupportedRequest,
    );
    expect(
      mutated((j) => j['requestType'] = 'future').kind,
      BattleRequestKind.unsupportedRequest,
    );
    expect(
      mutated((j) => j['active'][0]['moves'] = []).kind,
      BattleRequestKind.unsupportedRequest,
    );
  });

  test('disabled default, no PP, trapping and Tera availability', () {
    final result = mutated((j) {
      j['active'][0]['moves'][0].remove('disabled');
      j['active'][0]['canTerastallize'] = 'Electric';
      j['active'][0]['maybeTrapped'] = true;
      j['noCancel'] = true;
    });
    expect(result.moveSlots, [1]);
    expect(result.switchSlots, [2]);
    expect(result.canTerastallize, isTrue);
    expect(result.noCancel, isTrue);
    expect(result.active!.maybeTrapped, isTrue);
    final noMoves = mutated((j) {
      j['active'][0]['moves'][0]['pp'] = 0;
      j['active'][0]['canTerastallize'] = 'Electric';
    });
    expect(noMoves.moveSlots, isEmpty);
    expect(noMoves.canTerastallize, isFalse);
    expect(
      mutated((j) => j['active'][0]['canTerastallize'] = false).canTerastallize,
      isFalse,
    );
  });

  test('forced replacement does not apply voluntary trapping rules', () {
    final input = move();
    input.remove('active');
    input['forceSwitch'] = [true];
    input['side']['pokemon'][0]['condition'] = '0 fnt';
    final result = decodeBattleRequest(jsonEncode(input));
    expect(result.kind, BattleRequestKind.switchRequest);
    expect(result.side!.pokemon.first.condition.fainted, isTrue);
    expect(result.side!.pokemon.first.condition.maxHp, isNull);
    expect(result.switchSlots, [2]);
    input['forceSwitch'] = ['true'];
    expect(
      decodeBattleRequest(jsonEncode(input)).kind,
      BattleRequestKind.malformedRequest,
    );
  });

  test('wait, clear and failures never retain previous snapshot', () {
    final before = decodeBattleRequest(jsonEncode(move()));
    for (final payload in [
      'null',
      '{"wait":true}',
      '{',
      '{"teamPreview":true}',
    ]) {
      final result = decodeBattleRequest(payload);
      expect(result.moveSlots, isEmpty);
      expect(result.switchSlots, isEmpty);
      expect(result.active, isNull);
      expect(before.moveSlots, [1]);
    }
    final wait = decodeBattleRequest('{"wait":true}');
    expect(wait.noCancel, isTrue);
    expect(wait.rqid, isNull);
  });

  test('bounds and bad JSON never throw or expose private text', () {
    for (final text in [
      '',
      '[]',
      'true',
      '1',
      '"private"',
      '{"secret":',
      ' ' * (maxBattleRequestLength + 1),
      '${'[' * (maxBattleRequestDepth + 1)}0${']' * (maxBattleRequestDepth + 1)}',
    ]) {
      final result = decodeBattleRequest(text);
      expect(result.kind, BattleRequestKind.malformedRequest);
      expect(result.reason, 'invalidRequest');
      expect(result.toString(), isNot(contains('private')));
    }
    expect(
      mutated((j) => j['extra'] = r'brackets { [ \" ] }').kind,
      BattleRequestKind.move,
    );
  });

  test('room request event preserves source and rejected payloads replace too', () {
    final records = parseServerMessage(
      '>battle-test\n|request|${jsonEncode(move())}\n|request|{private\n|request|null\n|title|Next',
    );
    final events = records.map(decodeServerRecord).toList();
    final first = events[0] as BattleRequestEvent;
    expect(first.roomId, 'battle-test');
    expect(first.record, same(records[0]));
    expect(first.request.kind, BattleRequestKind.move);
    final bad = events[1] as BattleRequestEvent;
    expect(bad.request.kind, BattleRequestKind.malformedRequest);
    expect(bad.request.reason, isNot(contains('private')));
    expect(bad.toString(), isNot(contains('private')));
    expect(
      (events[2] as BattleRequestEvent).request.kind,
      BattleRequestKind.noRequest,
    );
    expect(events[3], isA<RoomTitleEvent>());
    expect(
      decodeServerRecord(parseServerMessage('|request|null').single),
      isA<MalformedServerEvent>(),
    );
  });
}
