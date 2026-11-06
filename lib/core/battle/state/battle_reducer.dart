import 'effect_observation.dart';
import 'battle_trait_reducer.dart';
export 'pokemon_traits.dart';
export 'effect_observation.dart';
import 'battle_environment_reducer.dart';
export 'battle_environment.dart';
import 'pokemon_effects.dart';
import '../../protocol/server_event_decoder.dart';
import 'battle_health.dart';
import 'battle_log_entry.dart';
import 'battle_phase.dart';
import 'battle_state.dart';
import 'observed_pokemon.dart';
import 'private_active_reference.dart';
import '../requests/battle_request_kind.dart';

export 'battle_state.dart';
export 'battle_phase.dart';
export 'battle_health.dart';
export 'battle_log_entry.dart';
export 'battle_player.dart';
export 'battle_result.dart';
export 'observed_pokemon.dart';
export 'battle_roster.dart';
export 'battle_appearance.dart';
export 'bench_status_observation.dart';
export 'private_active_reference.dart';

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
  if (event is BattleTraitEvent) {
    return reduceTraits(state, event) ?? _block(state);
  }
  if (event is BattleAttributedEvent) {
    final source = event.source;
    final of = source.ofIdent;
    if (of != null && publicActiveIdent(of) && !_known(state, of)) {
      return _block(state);
    }
    final next = reduceBattleEvent(
      state,
      event.inner,
      connectionEpoch: connectionEpoch,
    );
    if (!state.unsupported && next.unsupported) return _block(state);
    final first = event.record.data!.split('|').first;
    final target = publicIdent(first) ? first : null;
    // Annotation relations are preserved separately; no persistent trait inference.
    final owner =
        source.kind == EffectSourceKind.item ||
            source.kind == EffectSourceKind.ability
        ? of ?? target
        : source.kind == EffectSourceKind.move
        ? of
        : null;
    return recordEffect(next, event.record.eventType!, source, target, owner);
  }
  if (event is BattleEnvironmentEvent) {
    if (event.actor != null && !_known(state, event.actor!)) {
      return _block(state);
    }
    final environment = reduceEnvironment(state.environment, event, state.turn);
    return environment == null
        ? _block(state)
        : state.copyWith(environment: environment);
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
    return state.copyWith(
      turn: event.turn,
      roster: event.turn == state.turn
          ? state.roster
          : state.roster.updateActive(
              state.active.values.map(
                (p) => p.withEffects(p.effects.without({'protect'})),
              ),
            ),
    );
  }
  if (event is BattleRequestEvent) {
    final next = event.request;
    var updated = state.copyWith(
      request: next,
      requestRevision: state.requestRevision + 1,
      privateSide: next.side,
      clearPrivateActiveReference: true,
    );
    if (state.privateSide != null &&
        next.side != null &&
        state.privateSide!.id != next.side!.id) {
      updated = _block(updated);
    }
    final side = next.side;
    final appearanceId = side == null ? null : state.roster.activeIds[side.id];
    final activeSlots = side?.pokemon.where((p) => p.active).toList();
    if (!updated.unsupported &&
        (next.kind == BattleRequestKind.move ||
            next.kind == BattleRequestKind.switchRequest) &&
        appearanceId != null &&
        activeSlots?.length == 1) {
      updated = updated.copyWith(
        privateActiveReference: PrivateActiveReference(
          sideId: side!.id,
          requestRevision: updated.requestRevision,
          requestSlot: activeSlots!.single.slot,
          appearanceId: appearanceId,
        ),
      );
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
    var pokemon = event.pokemon;
    if (!_activeIdent(pokemon.ident)) return _block(state);
    if (event.source == 'move: Baton Pass' ||
        event.source == 'move: Shed Tail') {
      final previous = state.active[pokemon.sideId];
      if (event.dragged || previous == null || previous.health.fainted) {
        return _block(state);
      }
      if (event.source == 'move: Baton Pass' && previous.traits.suppressed) {
        return _block(
          state,
        ); // Gastro Acid copy exceptions need a separate audit.
      }
      pokemon = pokemon.withEffects(
        previous.effects.transferred(event.source!),
      );
    }
    return state.copyWith(
      roster: state.roster.enter(pokemon, state.turn),
      clearPrivateActiveReference:
          state.privateActiveReference?.sideId == pokemon.sideId,
    );
  }
  if (event is BattleEffectEvent) return _applyEffect(state, event);
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
    return state.copyWith(roster: state.roster.updateActive(active.values));
  }
  if (event is BattleStatusEvent) {
    if (event.cured && RegExp(r'^p[12]: \S(?:.*\S)?$').hasMatch(event.ident)) {
      return state.copyWith(
        roster: state.roster.observeBenchStatus(
          ident: event.ident,
          turn: state.turn,
          status: event.status,
          cured: event.cured,
        ),
      );
    }
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
      pokemon
          .withHealth(
            BattleHealth(hp: 0, maxHp: pokemon.health.maxHp, fainted: true),
          )
          .withEffects(const PokemonEffects.empty()),
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
        actorAppearanceId: state.roster.activeIds[event.actor.substring(0, 2)],
        actor: event.actor,
        action: event.action,
        cannotAct: event.cannotAct,
        target: event.target,
        attemptedMove: event.attemptedMove,
      ),
    ];
    final actor = state.active[event.actor.substring(0, 2)]!;
    return state.copyWith(
      roster: state.roster.updateActive([
        actor.withEffects(actor.effects.without({'destinybond'})),
      ]),
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
    state.copyWith(roster: state.roster.updateActive([pokemon]));
BattleState _block(BattleState state) =>
    state.copyWith(unsupported: true, clearPrivateActiveReference: true);
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
  '-nothing',
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
  'raw',
  'uhtml',
  'uhtmlchange',
};

BattleState _applyEffect(BattleState state, BattleEffectEvent event) {
  final p = event.arguments;
  final op = event.operation;
  if (op == '-clearallboost') {
    return state.copyWith(
      roster: state.roster.updateActive(
        state.active.values.map(
          (pokemon) => pokemon.withEffects(
            PokemonEffects(volatiles: pokemon.effects.volatiles),
          ),
        ),
      ),
    );
  }
  if (!_known(state, p[0])) return _block(state);
  final first = state.active[p[0].substring(0, 2)]!;
  if (first.health.fainted) return _block(state);
  final boosts = {...first.effects.boosts};
  final volatiles = {...first.effects.volatiles};
  if (op == '-swapboost' || op == '-copyboost') {
    if (!_known(state, p[1]) || p[0] == p[1]) return _block(state);
    final second = state.active[p[1].substring(0, 2)]!;
    if (second.health.fainted) return _block(state);
    final other = {...second.effects.boosts};
    final stats = p.length == 3 ? p[2].split(',') : battleStats;
    for (final stat in stats) {
      boosts[stat] = other[stat] ?? 0;
      if (op == '-swapboost') other[stat] = first.effects.boosts[stat] ?? 0;
    }
    boosts.removeWhere((_, value) => value == 0);
    other.removeWhere((_, value) => value == 0);
    return state.copyWith(
      roster: state.roster.updateActive([
        first.withEffects(PokemonEffects(boosts: boosts, volatiles: volatiles)),
        if (op == '-swapboost')
          second.withEffects(
            PokemonEffects(boosts: other, volatiles: second.effects.volatiles),
          ),
      ]),
    );
  }
  switch (op) {
    case '-boost':
    case '-unboost':
    case '-setboost':
      final amount = int.parse(p[2]);
      boosts[p[1]] = op == '-setboost'
          ? amount
          : ((boosts[p[1]] ?? 0) + (op == '-boost' ? amount : -amount)).clamp(
              -6,
              6,
            );
    case '-invertboost':
      boosts.updateAll((_, value) => -value);
    case '-clearboost':
      boosts.clear();
    case '-clearpositiveboost':
      if (p.length == 3 && !_known(state, p[1])) return _block(state);
      boosts.removeWhere((_, value) => value > 0);
    case '-clearnegativeboost':
      boosts.removeWhere((_, value) => value < 0);
    case '-start':
    case '-singleturn':
    case '-singlemove':
      volatiles[p[1]] = p.length == 3 ? p[2] : null;
    case '-end':
      volatiles.remove(p[1]);
  }
  boosts.removeWhere((_, value) => value == 0);
  return _replace(
    state,
    first.withEffects(PokemonEffects(boosts: boosts, volatiles: volatiles)),
  );
}
