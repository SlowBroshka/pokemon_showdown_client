import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/battle/scenario_runner.dart';
import '../../support/battle/inventory_validator.dart';

Map<String, dynamic> readCorpus(String name) =>
    jsonDecode(File('test/fixtures/battle/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final corpus = readCorpus('scenarios');
  final requests = BattleScenarioRunner.index([
    ...readCorpus('requests')['cases'] as List,
    ...readCorpus('mechanics_requests')['cases'] as List,
  ]);
  final setups = corpus['setups'] as Map<String, dynamic>;
  final cases = BattleScenarioRunner.index([
    ...corpus['cases'] as List,
    ...readCorpus('mechanics_scenarios')['cases'] as List,
  ]);
  final inventory = readCorpus('mechanics_inventory');
  final upstream = readCorpus('upstream_inventory');
  test(
    'inventory assigns every scanned type and resolves baseline references',
    () {
      validateBattleInventory(
        inventory,
        upstream,
        cases.keys.toSet(),
        requests.keys.toSet(),
      );
    },
  );
  test(
    'inventory rejects missing scenarios, sources, owners and event groups',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m['groups'][0]['scenarios'] = ['missing'],
        (m) => m['groups'][0]['sources'] = ['missing.ts'],
        (m) => m['groups'][0]['ownerPr'] = 0,
        (m) => m['groups'][0]['events'] = [],
        (m) => m['groups'][0]['current'] = 'fully-supported',
        (m) => m['revision'] = 'wrong',
        (m) => m['requestVariants'][0]['requestFixtures'] = ['missing'],
        (m) => m['requestVariants'][0]['requestFixtures'] = [],
      ]) {
        final copy = jsonDecode(jsonEncode(inventory)) as Map<String, dynamic>;
        mutate(copy);
        expect(
          () => validateBattleInventory(
            copy,
            upstream,
            cases.keys.toSet(),
            requests.keys.toSet(),
          ),
          throwsFormatException,
        );
      }
    },
  );
  for (final entry in cases.entries) {
    test('wire scenario: ${entry.key}', () async {
      await BattleScenarioRunner(setups, requests).run(entry.value);
    });
  }

  Map<String, dynamic> scenario(List<Map<String, dynamic>> steps) => {
    'id': 'runner-negative-test',
    'setup': 'initialized-battle',
    'steps': steps,
  };
  Future<void> rejects(List<Map<String, dynamic>> steps) async {
    await expectLater(
      BattleScenarioRunner(setups, requests).run(scenario(steps)),
      throwsA(isA<TestFailure>()),
    );
  }

  test('runner rejects unknown operation and expectation', () async {
    await rejects([
      {'recieve': '|turn|2'},
    ]);
    await rejects([
      {
        'expect': {'trun': 1},
      },
    ]);
    await rejects([
      {
        'expect': {
          'publicOwnHp': {'vlaue': 100},
        },
      },
    ]);
    await rejects([
      {
        'choose': {'kind': 'move', 'slot': 1, 'tera': true},
      },
    ]);
  });
  test('runner rejects broken references and ambiguous operations', () async {
    await rejects([
      {'requestFixture': 'missing'},
    ]);
    await rejects([
      {'submitCaptured': 'missing'},
    ]);
    await rejects([
      {
        'receive': '',
        'expect': {'turn': 1},
      },
    ]);
    await rejects([
      {'drainUpdates': true},
    ]);
    expect(
      () => BattleScenarioRunner.index([
        {'id': 'x'},
        {'id': 'x'},
      ]),
      throwsFormatException,
    );
  });
  test('runner detects wrong state and wrong or missing wire sends', () async {
    await rejects([
      {
        'expect': {'turn': 42},
      },
    ]);
    await rejects([
      {
        'expect': {'send': 'battle-contract-1|/choose move 1|7'},
      },
    ]);
    await rejects([
      {'requestFixture': 'move'},
      {
        'choose': {'kind': 'move', 'slot': 1},
      },
      {
        'expect': {'send': 'battle-contract-1|/choose move 2|7'},
      },
    ]);
    await rejects([
      {'requestFixture': 'move'},
      {
        'choose': {'kind': 'move', 'slot': 1},
      },
      {
        'expect': {'sendCount': 0},
      },
    ]);
  });
  test('runner proves source advances before delayed delivery', () async {
    await BattleScenarioRunner(setups, requests).run(
      scenario([
        {'requestFixture': 'move'},
        {
          'expect': {'canChoose': true, 'requestKind': 'move'},
        },
        {'enqueueRequestFixture': 'wait'},
        {
          'expect': {'canChoose': false, 'requestKind': 'move'},
        },
        {'drainUpdates': true},
        {
          'expect': {'canChoose': false, 'requestKind': 'wait'},
        },
      ]),
    );
  });
}
