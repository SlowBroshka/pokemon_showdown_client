import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_availability.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_decoder.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_kind.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_support_policy.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/protocol/server_message.dart';

const target = 'gen9randombattle';

void main() {
  final corpus = jsonDecode(
    File('test/fixtures/matchmaking/messages.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final c in (corpus['cases'] as List).cast<Map<String, dynamic>>().where(
    (c) => c['kind'] == 'formats',
  )) {
    test('formats corpus: ${c['id']}', () {
      final event = decodeServerRecord(
        parseServerMessage(c['wire'] as String).single,
      );
      final expected = c['expect'] as Map<String, dynamic>;
      if (expected['classification'] == 'wrongScope') {
        expect(event, isA<MalformedServerEvent>());
        return;
      }
      expect(event, isA<FormatsEvent>());
      final catalog = (event as FormatsEvent).catalog;
      expect(catalog.kind.name, expected['classification']);
      if (expected.containsKey('localLadder')) {
        expect(catalog.localLadder, expected['localLadder']);
      }
      bool eligible() =>
          formatAvailability(
            catalog,
            formatId: target,
            fresh: true,
            experimentalEnabled: true,
          ) ==
          FormatAvailability.experimental;
      if (expected.containsKey('experimentalEligible')) {
        expect(eligible(), expected['experimentalEligible']);
      }
      if (expected.containsKey('target')) {
        final wanted = expected['target'] as Map<String, dynamic>?;
        final format = catalog.formats[target];
        if (wanted == null) {
          expect(format, isNull);
        } else {
          expect(format, isNotNull);
          final actual = <String, Object?>{
            'id': format!.id,
            'flags': format.flags?.toInt(),
            'preset': format.preset,
            'searchShow': format.searchShow,
            'bestOfDefault': format.bestOfDefault,
            'unsupported': format.unsupported,
            'experimentalEligible': eligible(),
          };
          for (final field in wanted.entries) {
            expect(actual[field.key], field.value, reason: field.key);
          }
        }
      }
      if (catalog.kind != FormatCatalogKind.valid) expect(eligible(), isFalse);
    });
  }

  test('sections, empty section marker, LL and all metadata flags', () {
    final c = decodeFormatCatalog(
      ',LL|,2|First|[Gen 9] Random Battle,1df||Second|Other,0',
    );
    expect(c.kind, FormatCatalogKind.valid);
    final f = c.formats[target]!;
    expect(
      [f.section, f.column, f.name],
      ['First', 2, '[Gen 9] Random Battle'],
    );
    expect([
      f.preset,
      f.searchShow,
      f.challengeShow,
      f.tournamentShow,
      f.level50,
      f.bestOfDefault,
      f.teraPreviewDefault,
      f.itemClauseDefault,
    ], everyElement(isTrue));
    expect(f.partner, isFalse);
    expect(c.formats['other']!.section, 'Second');
    expect(c.formats['other']!.column, 2);
    expect(c.localLadder, isTrue);
    expect(() => c.formats.clear(), throwsUnsupportedError);
  });

  test('unknown high flags survive without enabling that entry', () {
    final c = decodeFormatCatalog(
      '[Gen 9] Random Battle,4f|Future,10000000000000000004f',
    );
    expect(
      c.formats['future']!.flags,
      BigInt.parse('10000000000000000004f', radix: 16),
    );
    expect(c.formats['future']!.unsupported, isTrue);
    expect(
      formatAvailability(
        c,
        formatId: target,
        fresh: true,
        experimentalEnabled: true,
      ),
      FormatAvailability.experimental,
    );
  });

  test('mixed legacy catalog closes availability even for modern entry', () {
    final c = decodeFormatCatalog('[Gen 9] Random Battle,4f|Old,,#');
    expect(c.kind, FormatCatalogKind.legacyUnsupported);
    expect(c.formats['old']!.flags, isNull);
    expect(
      formatAvailability(
        c,
        formatId: target,
        fresh: true,
        experimentalEnabled: true,
      ),
      FormatAvailability.legacyCatalog,
    );
  });

  test('malformed metadata discards partial entries', () {
    for (final suffix in [
      ',-1|Bad',
      ',LL|,LL',
      ',1|',
      ',1|,LL',
      ',999999999999999999999|Bad',
      '!!!,f',
      'Bad,0x4f',
      'Bad,+4f',
      'Bad,4f ',
      'Bad,4f\r',
      'Bad,4f\u0000',
    ]) {
      final c = decodeFormatCatalog('[Gen 9] Random Battle,4f|$suffix');
      expect(c.kind, FormatCatalogKind.malformed, reason: suffix);
      expect(c.formats, isEmpty);
    }
  });

  test('availability reasons and default-off experimental gate', () {
    FormatAvailability check(
      String payload, {
      String id = target,
      bool fresh = true,
      bool enabled = true,
    }) => formatAvailability(
      decodeFormatCatalog(payload),
      formatId: id,
      fresh: fresh,
      experimentalEnabled: enabled,
    );
    expect(
      formatAvailability(null, formatId: target, fresh: true),
      FormatAvailability.staleCatalog,
    );
    expect(
      check('[Gen 9] Random Battle,4f', fresh: false),
      FormatAvailability.staleCatalog,
    );
    expect(check('Broken,zz'), FormatAvailability.malformedCatalog);
    expect(check('Old,#'), FormatAvailability.legacyCatalog);
    expect(check(''), FormatAvailability.notAdvertised);
    expect(
      check('[Gen 9] OU,e', id: 'gen9ou'),
      FormatAvailability.unsupportedFormat,
    );
    expect(
      check('[Gen 9] Random Battle,6f'),
      FormatAvailability.unsupportedFlags,
    );
    expect(
      check('[Gen 9] Random Battle,4d'),
      FormatAvailability.searchDisabled,
    );
    expect(check('[Gen 9] Random Battle,4e'), FormatAvailability.teamRequired);
    expect(
      check('[Gen 9] Random Battle,4f', enabled: false),
      FormatAvailability.experimentalDisabled,
    );
    expect(
      formatAvailability(
        decodeFormatCatalog('[Gen 9] Random Battle,4f'),
        formatId: target,
        fresh: true,
      ),
      FormatAvailability.experimentalDisabled,
    );
    expect(check('[Gen 9] Random Battle,4f'), FormatAvailability.experimental);
    expect(
      check('[Gen 9] Random Battle,4f', id: '[Gen 9] Random Battle'),
      FormatAvailability.notAdvertised,
    );
  });
}
