import '../requests/pokemon_status.dart';
import 'battle_appearance.dart';
import 'bench_status_observation.dart';
import 'observed_pokemon.dart';

const maxBattleAppearances = 128;
const maxBenchStatusObservations = 128;

/// Bounded public evidence, never a deduplicated or inferred six-member team.
/// Inactive appearance snapshots are historical, not current bench HP/status.
final class BattleRoster {
  BattleRoster._({
    required Map<int, BattleAppearance> appearances,
    required Map<String, int> activeIds,
    required List<BenchStatusObservation> benchStatuses,
    required this.nextId,
    required this.historyTruncated,
  }) : appearances = Map.unmodifiable(appearances),
       activeIds = Map.unmodifiable(activeIds),
       benchStatuses = List.unmodifiable(benchStatuses);

  factory BattleRoster.empty() => BattleRoster._(
    appearances: {},
    activeIds: {},
    benchStatuses: [],
    nextId: 1,
    historyTruncated: false,
  );

  final Map<int, BattleAppearance> appearances;
  final Map<String, int> activeIds;
  final List<BenchStatusObservation> benchStatuses;
  final int nextId;
  final bool historyTruncated;

  Map<String, ObservedPokemon> get active => Map.unmodifiable({
    for (final entry in activeIds.entries)
      entry.key: appearances[entry.value]!.pokemon,
  });

  BattleRoster enter(ObservedPokemon pokemon, int turn) {
    final previous = appearances.values
        .where(
          (entry) =>
              entry.pokemon.ident == pokemon.ident &&
              entry.pokemon.details == pokemon.details,
        )
        .map((entry) => entry.id);
    final entries = {
      ...appearances,
      nextId: BattleAppearance(
        id: nextId,
        enteredTurn: turn,
        pokemon: pokemon,
        samePresentationIds: previous,
      ),
    };
    final active = {...activeIds, pokemon.sideId: nextId};
    var truncated = historyTruncated;
    while (entries.length > maxBattleAppearances) {
      entries.remove(
        entries.keys.firstWhere((id) => !active.containsValue(id)),
      );
      truncated = true;
    }
    final retained = entries.keys.toSet();
    return BattleRoster._(
      appearances: {
        for (final entry in entries.entries)
          entry.key: entry.value.retainingReferences(retained),
      },
      activeIds: active,
      benchStatuses: [
        for (final report in benchStatuses)
          report.retainingReferences(retained),
      ],
      nextId: nextId + 1,
      historyTruncated: truncated,
    );
  }

  /// Reducer validates the entire event before calling this, including sethp.
  BattleRoster updateActive(Iterable<ObservedPokemon> pokemon) {
    final entries = {...appearances};
    for (final value in pokemon) {
      final id = activeIds[value.sideId];
      if (id == null || entries[id]!.pokemon.ident != value.ident) {
        throw StateError('Unknown active appearance');
      }
      entries[id] = entries[id]!.withPokemon(value);
    }
    return BattleRoster._(
      appearances: entries,
      activeIds: activeIds,
      benchStatuses: benchStatuses,
      nextId: nextId,
      historyTruncated: historyTruncated,
    );
  }

  BattleRoster observeBenchStatus({
    required String ident,
    required int turn,
    required PokemonStatus status,
    required bool cured,
  }) {
    final side = ident.substring(0, 2);
    final name = ident.substring(4);
    final candidates = appearances.values
        .where(
          (entry) =>
              !activeIds.containsValue(entry.id) &&
              entry.pokemon.sideId == side &&
              entry.pokemon.ident.substring(5) == name,
        )
        .map((entry) => entry.id);
    final reports = [
      ...benchStatuses,
      BenchStatusObservation(
        ident: ident,
        turn: turn,
        status: status,
        cured: cured,
        candidateAppearanceIds: candidates,
      ),
    ];
    final overflow = reports.length > maxBenchStatusObservations;
    return BattleRoster._(
      appearances: appearances,
      activeIds: activeIds,
      benchStatuses: overflow
          ? reports.sublist(reports.length - maxBenchStatusObservations)
          : reports,
      nextId: nextId,
      historyTruncated: historyTruncated || overflow,
    );
  }
}
