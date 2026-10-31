import 'scenario_runner.dart';

/// Validates the manifest graph independently from scenario execution.
void validateBattleInventory(
  Map<String, dynamic> inventory,
  Map<String, dynamic> upstream,
  Set<String> scenarioIds,
  Set<String> requestIds,
) {
  void require(bool value, String reason) {
    if (!value) throw FormatException(reason);
  }

  BattleScenarioRunner.keys(inventory, {
    'schemaVersion',
    'format',
    'revision',
    'coverageMeaning',
    'groups',
    'requestVariants',
    'openQuestions',
  });
  require(inventory['schemaVersion'] == 1, 'Unsupported inventory version');
  require(inventory['format'] == 'gen9randombattle', 'Unexpected format');
  require(inventory['revision'] == upstream['revision'], 'Revision mismatch');
  require(
    RegExp(r'^[a-f0-9]{40}$').hasMatch(inventory['revision'] as String),
    'Invalid SHA',
  );
  final sources = upstream['sources'] as Map;
  final documented = (upstream['documentedEvents'] as List)
      .cast<String>()
      .toSet();
  final emitted = (upstream['literalEmitters'] as Map).keys
      .cast<String>()
      .toSet();
  final assigned = <String>{};
  final ids = <String>{};
  for (final raw in inventory['groups'] as List) {
    final group = raw as Map;
    BattleScenarioRunner.keys(group, {
      'id',
      'events',
      'ownerPr',
      'current',
      'target',
      'reachability',
      'sources',
      'scenarios',
    });
    require(ids.add(group['id'] as String), 'Duplicate group');
    require(
      group['ownerPr'] is int && group['ownerPr'] >= 2 && group['ownerPr'] <= 9,
      'Missing owner PR',
    );
    require(
      {'partial', 'blocked', 'ignored', 'mixed'}.contains(group['current']),
      'Unknown support status',
    );
    require(
      {
        'in-scope',
        'out-of-scope',
        'requires-audit',
        'pool-witness',
        'deferred',
      }.contains(group['reachability']),
      'Unknown reachability',
    );
    require((group['target'] as String).trim().isNotEmpty, 'Missing target');
    require((group['scenarios'] as List).isNotEmpty, 'No executable baseline');
    for (final id in group['scenarios'] as List) {
      require(scenarioIds.contains(id), 'Unknown scenario: $id');
    }
    require((group['sources'] as List).isNotEmpty, 'No source');
    for (final path in group['sources'] as List) {
      require(sources.containsKey(path), 'Unknown source: $path');
    }
    for (final event in group['events'] as List) {
      require(
        assigned.add(event as String),
        'Duplicate event ownership: $event',
      );
    }
  }
  require(
    assigned.difference({...documented, ...emitted}).isEmpty,
    'Uninventoried event',
  );
  require(
    {...documented, ...emitted}.difference(assigned).isEmpty,
    'Missing event ownership',
  );
  final variants = <String>{};
  final assignedRequests = <String>{};
  for (final raw in inventory['requestVariants'] as List) {
    final variant = raw as Map;
    BattleScenarioRunner.keys(variant, {
      'id',
      'current',
      'ownerPr',
      'scenarios',
      'target',
      'requestFixtures',
    });
    require(variants.add(variant['id'] as String), 'Duplicate request variant');
    require(variant['ownerPr'] == 7, 'Wrong request owner');
    require(
      {
        'supported',
        'partial',
        'blocked',
        'guarded',
      }.contains(variant['current']),
      'Unknown request status',
    );
    require(
      (variant['target'] as String).trim().isNotEmpty,
      'Missing request target',
    );
    require((variant['scenarios'] as List).isNotEmpty, 'No request baseline');
    for (final id in variant['requestFixtures'] as List) {
      require(requestIds.contains(id), 'Unknown request fixture: $id');
      require(
        assignedRequests.add(id as String),
        'Duplicate request ownership: $id',
      );
    }
    for (final id in variant['scenarios'] as List) {
      require(scenarioIds.contains(id), 'Unknown request scenario: $id');
    }
  }
  require(
    requestIds.difference(assignedRequests).isEmpty,
    'Unassigned request fixture',
  );
}
