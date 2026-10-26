import '../../protocol/server_event_decoder.dart';
import 'battle_health.dart';
import 'battle_log_entry.dart';
import 'battle_phase.dart';
import 'battle_state.dart';
import 'observed_pokemon.dart';

export 'battle_state.dart';
export 'battle_phase.dart';
export 'battle_health.dart';
export 'battle_log_entry.dart';
export 'battle_player.dart';
export 'battle_result.dart';
export 'observed_pokemon.dart';

const maxBattleLogEntries = 200;

/// Caller passes the epoch from SessionUpdate, never the current epoch by guess.
BattleState reduceBattleEvent(
  BattleState state,
  ServerEvent event, {
  required int connectionEpoch,
}) {
  if (state.connectionEpoch != connectionEpoch ||
      event.roomId != state.roomId ||
      state.stale) {
    return state;
  }
  if (event is RoomDeinitEvent) {
    return state.copyWith(phase: BattlePhase.closed, clearRequest: true);
  }
  if (state.terminal) return state;
  if (event is RoomInitEvent) {
    if (state.phase != BattlePhase.uninitialized) return state;
    return state.copyWith(
      phase: BattlePhase.initialized,
      unsupported: event.roomType != 'battle',
    );
  }
  if (state.phase == BattlePhase.uninitialized) return state;
  if (event is RoomTitleEvent) return state.copyWith(title: event.title);
  if (event is MalformedServerEvent) return _block(state);
  if (event is UnknownServerEvent) {
    return _decorative.contains(event.eventType) ? state : _block(state);
  }
  if (event is BattlePlayerEvent) {
    final player = event.player;
    if (!_supportedSide(player.sideId)) return _block(state);
    return state.copyWith(players: {...state.players, player.sideId: player});
  }
  if (event is BattleMetadataEvent) {
    switch (event.kind) {
      case BattleMetadataKind.generation:
        if (event.number != 9) {
          return _block(state.copyWith(generation: event.number));
        }
        return state.copyWith(generation: event.number);
      case BattleMetadataKind.gameType:
        if (event.text != 'singles') {
          return _block(state.copyWith(gameType: event.text));
        }
        return state.copyWith(gameType: event.text);
      case BattleMetadataKind.tier:
        return state.copyWith(tier: event.text);
      case BattleMetadataKind.teamSize:
        if (!_supportedSide(event.sideId!) ||
            event.number! < 1 ||
            event.number! > 6) {
          return _block(state);
        }
        return state.copyWith(
          teamSizes: {...state.teamSizes, event.sideId!: event.number!},
        );
    }
  }
  if (event is BattleStartEvent) {
    return state.copyWith(phase: BattlePhase.started);
  }
  if (event is BattleTurnEvent) {
    if (event.turn < state.turn) return _block(state);
    return state.copyWith(turn: event.turn);
  }
  if (event is BattleRequestEvent) {
    final next = event.request;
    var updated = state.copyWith(
      request: next,
      requestRevision: state.requestRevision + 1,
      privateSide: next.side,
    );
    if (state.privateSide != null &&
        next.side != null &&
        state.privateSide!.id != next.side!.id) {
      updated = _block(updated);
    }
    return updated;
  }
  if (event is BattleEndEvent) {
    return state.copyWith(
      phase: BattlePhase.finished,
      result: event.result,
      clearRequest: true,
    );
  }
  if (event is BattleSwitchEvent) {
    final pokemon = event.pokemon;
    if (!_activeIdent(pokemon.ident)) return _block(state);
    return state.copyWith(active: {...state.active, pokemon.sideId: pokemon});
  }
  if (event is BattleHealthEvent) {
    // Validate the entire multi-target update before applying any portion.
    if (event.changes.any((change) => !_known(state, change.ident))) {
      return _block(state);
    }
    final active = {...state.active};
    for (final change in event.changes) {
      final side = change.ident.substring(0, 2);
      active[side] = active[side]!.withHealth(change.health);
    }
    return state.copyWith(active: active);
  }
  if (event is BattleStatusEvent) {
    if (!_known(state, event.ident)) return _block(state);
    final pokemon = state.active[event.ident.substring(0, 2)]!;
    if (event.cured &&
        pokemon.health.status != null &&
        pokemon.health.status != event.status) {
      return _block(state);
    }
    return _replace(
      state,
      pokemon.withHealth(
        pokemon.health.withStatus(event.cured ? null : event.status),
      ),
    );
  }
  if (event is BattleFaintEvent) {
    if (!_known(state, event.ident)) return _block(state);
    final pokemon = state.active[event.ident.substring(0, 2)]!;
    return _replace(
      state,
      pokemon.withHealth(
        BattleHealth(hp: 0, maxHp: pokemon.health.maxHp, fainted: true),
      ),
    );
  }
  if (event is BattleTeraEvent) {
    if (!_known(state, event.ident)) return _block(state);
    return _replace(
      state,
      state.active[event.ident.substring(0, 2)]!.withTera(event.teraType),
    );
  }
  if (event is BattleActionEvent) {
    if (!_known(state, event.actor)) return _block(state);
    final entries = [
      ...state.log,
      BattleLogEntry(
        turn: state.turn,
        actor: event.actor,
        action: event.action,
        cannotAct: event.cannotAct,
        target: event.target,
        attemptedMove: event.attemptedMove,
      ),
    ];
    return state.copyWith(
      log: entries.length <= maxBattleLogEntries
          ? entries
          : entries.sublist(entries.length - maxBattleLogEntries),
    );
  }
  // Ordinary text, popup and errors are not field changes or choice acknowledgments.
  if (event is PlainTextEvent ||
      event is ServerErrorEvent ||
      event is PopupEvent) {
    return state;
  }
  return _block(state);
}

BattleState _replace(BattleState state, ObservedPokemon pokemon) =>
    state.copyWith(active: {...state.active, pokemon.sideId: pokemon});
BattleState _block(BattleState state) => state.copyWith(unsupported: true);
bool _supportedSide(String side) => side == 'p1' || side == 'p2';
bool _activeIdent(String ident) =>
    ident.startsWith('p1a: ') || ident.startsWith('p2a: ');
bool _known(BattleState state, String ident) =>
    _activeIdent(ident) && state.active[ident.substring(0, 2)]?.ident == ident;
const _decorative = {
  't:',
  'seed',
  'rated',
  'rule',
  'clearpoke',
  'poke',
  'upkeep',
  'inactive',
  'inactiveoff',
  'c',
  'c:',
  'j',
  'l',
  'n',
  'chat',
  'join',
  'leave',
  'name',
  'message',
  '-message',
  '-hint',
  '-anim',
  '-crit',
  '-supereffective',
  '-resisted',
  '-miss',
  '-fail',
  '-immune',
  '-notarget',
  'html',
  'uhtml',
  'uhtmlchange',
};
