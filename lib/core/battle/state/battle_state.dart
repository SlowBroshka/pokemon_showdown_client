import '../requests/battle_request.dart';
import '../requests/request_side.dart';
import 'battle_phase.dart';
import 'battle_player.dart';
import 'battle_result.dart';
import 'battle_log_entry.dart';
import 'observed_pokemon.dart';

/// Projection of one room in one connection epoch. No network or UI ownership.
final class BattleState {
  BattleState({
    required this.roomId,
    required this.connectionEpoch,
    this.phase = BattlePhase.uninitialized,
    this.title,
    this.generation,
    this.gameType,
    this.tier,
    this.turn = 0,
    this.stale = false,
    this.unsupported = false,
    this.request,
    this.requestRevision = 0,
    this.privateSide,
    this.result,
    Map<String, BattlePlayer> players = const {},
    Map<String, int> teamSizes = const {},
    Map<String, ObservedPokemon> active = const {},
    List<BattleLogEntry> log = const [],
  }) : players = Map.unmodifiable(players),
       teamSizes = Map.unmodifiable(teamSizes),
       active = Map.unmodifiable(active),
       log = List.unmodifiable(log);
  final String roomId;
  final int connectionEpoch;
  final BattlePhase phase;
  final String? title;
  final int? generation;
  final String? gameType;
  final String? tier;
  final int turn;
  final bool stale;
  final bool unsupported;
  final Map<String, BattlePlayer> players;
  final Map<String, int> teamSizes;
  final Map<String, ObservedPokemon> active;
  final List<BattleLogEntry> log;
  final BattleRequest? request;
  final int requestRevision;

  /// Last private snapshot, not a live merge with public HP events.
  final RequestSide? privateSide;
  final BattleResult? result;
  bool get terminal =>
      phase == BattlePhase.finished || phase == BattlePhase.closed;
  bool get compatible =>
      !unsupported && generation == 9 && gameType == 'singles';
  BattleState markStale() => copyWith(stale: true, clearRequest: true);

  BattleState copyWith({
    BattlePhase? phase,
    String? title,
    int? generation,
    String? gameType,
    String? tier,
    int? turn,
    bool? stale,
    bool? unsupported,
    BattleRequest? request,
    bool clearRequest = false,
    int? requestRevision,
    RequestSide? privateSide,
    BattleResult? result,
    Map<String, BattlePlayer>? players,
    Map<String, int>? teamSizes,
    Map<String, ObservedPokemon>? active,
    List<BattleLogEntry>? log,
  }) => BattleState(
    roomId: roomId,
    connectionEpoch: connectionEpoch,
    phase: phase ?? this.phase,
    title: title ?? this.title,
    generation: generation ?? this.generation,
    gameType: gameType ?? this.gameType,
    tier: tier ?? this.tier,
    turn: turn ?? this.turn,
    stale: stale ?? this.stale,
    unsupported: unsupported ?? this.unsupported,
    request: clearRequest ? null : request ?? this.request,
    requestRevision: requestRevision ?? this.requestRevision,
    privateSide: privateSide ?? this.privateSide,
    result: result ?? this.result,
    players: players ?? this.players,
    teamSizes: teamSizes ?? this.teamSizes,
    active: active ?? this.active,
    log: log ?? this.log,
  );
}
