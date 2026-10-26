import 'battle_events/battle_action_event.dart';
import 'battle_events/battle_end_event.dart';
import 'battle_events/battle_faint_event.dart';
import 'battle_events/battle_health_event.dart';
import 'battle_events/battle_metadata_event.dart';
import 'battle_events/battle_metadata_kind.dart';
import 'battle_events/battle_player_event.dart';
import 'battle_events/battle_start_event.dart';
import 'battle_events/battle_status_event.dart';
import 'battle_events/battle_switch_event.dart';
import 'battle_events/battle_tera_event.dart';
import 'battle_events/battle_turn_event.dart';

import '../battle/requests/pokemon_status.dart';
import '../battle/state/battle_health.dart';
import '../battle/state/battle_health_change.dart';
import '../battle/state/battle_player.dart';
import '../battle/state/battle_result.dart';
import '../battle/state/observed_pokemon.dart';
import 'events/malformed_server_event.dart';
import 'server_event.dart';
import 'server_record.dart';

export 'battle_events/battle_action_event.dart';
export 'battle_events/battle_end_event.dart';
export 'battle_events/battle_faint_event.dart';
export 'battle_events/battle_health_event.dart';
export 'battle_events/battle_metadata_event.dart';
export 'battle_events/battle_metadata_kind.dart';
export 'battle_events/battle_player_event.dart';
export 'battle_events/battle_start_event.dart';
export 'battle_events/battle_status_event.dart';
export 'battle_events/battle_switch_event.dart';
export 'battle_events/battle_tera_event.dart';
export 'battle_events/battle_turn_event.dart';

const _types = {
  'player',
  'teamsize',
  'gametype',
  'gen',
  'tier',
  'start',
  'turn',
  'switch',
  'drag',
  'move',
  'cant',
  '-damage',
  '-heal',
  '-sethp',
  '-status',
  '-curestatus',
  'faint',
  '-terastallize',
  'win',
  'tie',
};

/// null means this decoder does not own the type. Failures never include input.
ServerEvent? decodeBattleEvent(ServerRecord record) {
  final type = record.eventType;
  if (!_types.contains(type)) return null;
  try {
    if (record.roomId == null || record.data == null) _bad();
    final data = record.data!;
    // Trailing protocol annotations are allowed only for actions below.
    final all = data.split('|');
    final annotation = all.indexWhere((p) => p.startsWith('['));
    final tagged = {
      'switch',
      'drag',
      'move',
      'cant',
      '-damage',
      '-heal',
      '-sethp',
      '-status',
      '-curestatus',
      'faint',
      '-terastallize',
    };
    final parts = tagged.contains(type) && annotation >= 0
        ? all.sublist(0, annotation)
        : all;
    if (tagged.contains(type) &&
        annotation >= 0 &&
        all.skip(annotation).any((p) => !p.startsWith('['))) {
      _bad();
    }
    switch (type) {
      case 'player':
        if (parts.length < 2 || parts.length > 4) _bad();
        return BattlePlayerEvent(
          record,
          player: BattlePlayer(
            sideId: _side(parts[0]),
            name: parts[1],
            avatar: parts.length >= 3 ? parts[2] : null,
            rating: parts.length == 4 ? parts[3] : null,
          ),
        );
      case 'teamsize':
        _count(parts, 2);
        return BattleMetadataEvent(
          record,
          kind: BattleMetadataKind.teamSize,
          sideId: _side(parts[0]),
          number: _number(parts[1]),
        );
      case 'gen':
        _count(parts, 1);
        return BattleMetadataEvent(
          record,
          kind: BattleMetadataKind.generation,
          number: _number(parts[0]),
        );
      case 'gametype':
      case 'tier':
        _count(parts, 1);
        return BattleMetadataEvent(
          record,
          kind: type == 'tier'
              ? BattleMetadataKind.tier
              : BattleMetadataKind.gameType,
          text: _text(parts[0]),
        );
      case 'start':
        if (data.isNotEmpty) _bad();
        return BattleStartEvent(record);
      case 'turn':
        _count(parts, 1);
        final turn = _number(parts[0]);
        if (turn == 0) _bad();
        return BattleTurnEvent(record, turn: turn);
      case 'switch':
      case 'drag':
        _count(parts, 3);
        final details = _text(parts[1]);
        final teraParts = details
            .split(', ')
            .where((p) => p.startsWith('tera:'))
            .toList();
        if (teraParts.length > 1) _bad();
        return BattleSwitchEvent(
          record,
          dragged: type == 'drag',
          pokemon: ObservedPokemon(
            ident: _ident(parts[0]),
            details: details,
            health: _health(parts[2]),
            teraType: teraParts.isEmpty
                ? null
                : _text(teraParts.single.substring(5)),
          ),
        );
      case '-damage':
      case '-heal':
      case '-sethp':
        if (parts.length != 2 && !(type == '-sethp' && parts.length == 4)) {
          _bad();
        }
        final changes = <BattleHealthChange>[];
        for (var i = 0; i < parts.length; i += 2) {
          changes.add(
            BattleHealthChange(
              ident: _ident(parts[i]),
              health: _health(parts[i + 1]),
            ),
          );
        }
        if (changes.map((c) => c.ident).toSet().length != changes.length) {
          _bad();
        }
        return BattleHealthEvent(record, changes: changes);
      case '-status':
      case '-curestatus':
        _count(parts, 2);
        return BattleStatusEvent(
          record,
          ident: _ident(parts[0]),
          status: _status(parts[1]),
          cured: type == '-curestatus',
        );
      case 'faint':
        _count(parts, 1);
        return BattleFaintEvent(record, ident: _ident(parts[0]));
      case '-terastallize':
        _count(parts, 2);
        return BattleTeraEvent(
          record,
          ident: _ident(parts[0]),
          teraType: _text(parts[1]),
        );
      case 'move':
      case 'cant':
        if (parts.length < 2 || parts.length > 3) _bad();
        final extra = parts.length == 3 && parts[2].isNotEmpty
            ? parts[2]
            : null;
        return BattleActionEvent(
          record,
          actor: _ident(parts[0]),
          action: _text(parts[1]),
          cannotAct: type == 'cant',
          target: type == 'move' && extra != null ? _ident(extra) : null,
          attemptedMove: type == 'cant' ? extra : null,
        );
      case 'win':
        _count(parts, 1);
        return BattleEndEvent(record, result: BattleResult.win(_text(data)));
      case 'tie':
        if (data.isNotEmpty) _bad();
        return BattleEndEvent(record, result: const BattleResult.tie());
    }
    return null;
  } on FormatException {
    return MalformedServerEvent(record, reason: 'Invalid battle event');
  }
}

String _text(String value) {
  if (value.trim().isEmpty) _bad();
  return value;
}

String _side(String value) {
  if (!RegExp(r'^p[1-4]$').hasMatch(value)) _bad();
  return value;
}

String _ident(String value) {
  if (!RegExp(r'^p[1-4][a-c]?: .+\S$').hasMatch(value) &&
      !RegExp(r'^p[1-4][a-c]?: \S$').hasMatch(value)) {
    _bad();
  }
  return value;
}

int _number(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value)) _bad();
  final number = int.tryParse(value);
  if (number == null || number > 9007199254740991) _bad();
  return number;
}

PokemonStatus _status(String value) {
  for (final status in PokemonStatus.values) {
    if (status.name == value) return status;
  }
  _bad();
}

BattleHealth _health(String value) {
  if (value == '0 fnt') {
    return const BattleHealth(hp: 0, maxHp: null, fainted: true);
  }
  final match = RegExp(r'^(\d+)/(\d+)(?: (brn|par|psn|tox|slp|frz))?$')
      .firstMatch(value);
  if (match == null) _bad();
  final hp = _number(match.group(1)!);
  final max = _number(match.group(2)!);
  if (max == 0 || hp > max) _bad();
  return BattleHealth(
    hp: hp,
    maxHp: max,
    fainted: hp == 0,
    status: match.group(3) == null ? null : _status(match.group(3)!),
  );
}

void _count(List<String> parts, int n) {
  if (parts.length != n) _bad();
}

Never _bad() => throw const FormatException('Invalid battle event');
