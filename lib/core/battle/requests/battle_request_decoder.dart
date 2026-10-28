import 'dart:convert';

import 'battle_request.dart';
import 'battle_request_kind.dart';
import 'pokemon_condition.dart';
import 'pokemon_status.dart';
import 'request_active.dart';
import 'request_move.dart';
import 'request_pokemon.dart';
import 'request_side.dart';

export 'battle_request.dart';
export 'battle_request_kind.dart';
export 'pokemon_condition.dart';
export 'pokemon_status.dart';
export 'request_active.dart';
export 'request_move.dart';
export 'request_pokemon.dart';
export 'request_side.dart';

/// Limits are client policy, measured in UTF-16 code units and JSON depth.
const maxBattleRequestLength = 262144;
const maxBattleRequestDepth = 32;

/// Stateless decoder. Rejected requests contain no usable actions or private data.
BattleRequest decodeBattleRequest(String payload) {
  try {
    _checkBounds(payload);
    final value = jsonDecode(payload);
    if (value == null) {
      return const BattleRequest(kind: BattleRequestKind.noRequest);
    }
    return _decode(_object(value));
  } on FormatException {
    return const BattleRequest(
      kind: BattleRequestKind.malformedRequest,
      reason: 'invalidRequest',
    );
  } on UnsupportedError {
    return const BattleRequest(
      kind: BattleRequestKind.unsupportedRequest,
      reason: 'unsupportedRequest',
    );
  }
}

BattleRequest _decode(Map<String, dynamic> json) {
  final rqid = json.containsKey('rqid') ? _integer(json['rqid']) : null;
  final noCancel = _flag(json, 'noCancel');
  final wait = _flag(json, 'wait');
  final preview = _flag(json, 'teamPreview');
  final hasActive = json.containsKey('active');
  final hasSwitch = json.containsKey('forceSwitch');
  if ([wait, preview, hasActive, hasSwitch].where((v) => v).length != 1) {
    _bad();
  }
  final String kind = wait
      ? 'wait'
      : preview
      ? 'team'
      : hasSwitch
      ? 'switch'
      : 'move';
  if (json.containsKey('requestType')) {
    final explicit = _text(json['requestType']);
    if (!{'wait', 'team', 'switch', 'move'}.contains(explicit)) _unsupported();
    if (explicit != kind) _bad();
  }
  if (preview || json.containsKey('ally') || _flag(json, 'targetable')) {
    _unsupported();
  }
  if (wait) {
    return BattleRequest(
      kind: BattleRequestKind.wait,
      rqid: rqid,
      noCancel: true,
      side: json.containsKey('side') ? _side(json['side']) : null,
    );
  }
  if (hasSwitch) {
    final switches = _list(json['forceSwitch']);
    if (switches.any((v) => v is! bool)) _bad();
    if (switches.length != 1 || switches.single != true) _unsupported();
    final side = _side(json['side']);
    if (side.pokemon.where((p) => p.active).length != 1) _bad();
    return BattleRequest(
      kind: BattleRequestKind.switchRequest,
      rqid: rqid,
      noCancel: noCancel,
      side: side,
    );
  }
  final activeList = _list(json['active']);
  if (activeList.length != 1) _unsupported();
  final side = _side(json['side']);
  final activePokemon = side.pokemon.where((p) => p.active).toList();
  if (activePokemon.length != 1 || activePokemon.single.condition.fainted) {
    _bad();
  }
  final active = _active(_object(activeList.single));
  return BattleRequest(
    kind: BattleRequestKind.move,
    rqid: rqid,
    noCancel: noCancel,
    side: side,
    active: active,
  );
}

RequestSide _side(Object? value) {
  final json = _object(value);
  final id = _text(json['id']);
  if (id == 'p3' || id == 'p4') _unsupported();
  if (id != 'p1' && id != 'p2') _bad();
  final pokemon = _list(json['pokemon']);
  if (pokemon.isEmpty || pokemon.length > 6) _bad();
  return RequestSide(
    id: id,
    name: _optionalText(json, 'name'),
    pokemon: [
      for (var i = 0; i < pokemon.length; i++)
        _pokemon(_object(pokemon[i]), id, i + 1),
    ],
  );
}

RequestPokemon _pokemon(Map<String, dynamic> json, String sideId, int slot) {
  // These change the semantics of switch/pass; never treat them as a normal slot.
  if (_flag(json, 'reviving') || _flag(json, 'commanding')) _unsupported();
  final ident = _text(json['ident']);
  if (!ident.startsWith('$sideId: ') || ident.length <= 4) _bad();
  final moves = json.containsKey('moves')
      ? _list(json['moves']).map((v) => _text(v)).toList()
      : <String>[];
  final stats = <String, int>{};
  if (json.containsKey('stats')) {
    for (final entry in _object(json['stats']).entries) {
      stats[entry.key] = _integer(entry.value);
    }
  }
  if (json['active'] is! bool) _bad();
  return RequestPokemon(
    slot: slot,
    ident: ident,
    details: _text(json['details']),
    condition: _condition(_text(json['condition'])),
    active: json['active'] as bool,
    moves: moves,
    stats: stats,
    item: _optionalText(json, 'item', empty: true),
    ability: _optionalText(json, 'ability', empty: true),
    baseAbility: _optionalText(json, 'baseAbility', empty: true),
    teraType: _optionalText(json, 'teraType'),
    terastallized: _typeOrFalse(json, 'terastallized', empty: true),
  );
}

PokemonCondition _condition(String text) {
  if (text == '0 fnt') {
    return const PokemonCondition(hp: 0, maxHp: null, fainted: true);
  }
  final match = RegExp(r'^(\d+)/(\d+)(?: (brn|par|psn|tox|slp|frz))?$')
      .firstMatch(text);
  if (match == null) _bad();
  final hp = int.tryParse(match.group(1)!);
  final max = int.tryParse(match.group(2)!);
  if (hp == null || max == null || hp <= 0 || max <= 0 || hp > max) _bad();
  final status = match.group(3);
  return PokemonCondition(
    hp: hp,
    maxHp: max,
    fainted: false,
    status: status == null ? null : PokemonStatus.values.byName(status),
  );
}

RequestActive _active(Map<String, dynamic> json) {
  for (final flag in [
    'canMegaEvo',
    'canMegaEvoX',
    'canMegaEvoY',
    'canUltraBurst',
    'canDynamax',
  ]) {
    if (_flag(json, flag)) _unsupported();
  }
  for (final key in ['canZMove', 'zMoves', 'maxMoves']) {
    if (json.containsKey(key) && json[key] != null && json[key] != false) {
      _unsupported();
    }
  }
  final moves = _list(json['moves']);
  if (moves.isEmpty || moves.length > 4) _unsupported();
  final decoded = [
    for (var i = 0; i < moves.length; i++) _move(_object(moves[i]), i + 1),
  ];
  if (decoded.any((m) => m.id == 'struggle') && decoded.length != 1) _bad();
  return RequestActive(
    moves: decoded,
    trapped: _flag(json, 'trapped'),
    maybeTrapped: _flag(json, 'maybeTrapped'),
    maybeDisabled: _flag(json, 'maybeDisabled'),
    maybeLocked: _flag(json, 'maybeLocked'),
    canTerastallize: _typeOrFalse(json, 'canTerastallize'),
  );
}

RequestMove _move(Map<String, dynamic> json, int slot) {
  final name = _text(json['move']);
  final id = _text(json['id']);
  final target = _text(json['target']);
  if (!const {
    'normal',
    'self',
    'adjacentFoe',
    'allAdjacentFoes',
    'allAdjacent',
    'any',
    'randomNormal',
    'all',
    'allySide',
    'foeSide',
    'allyTeam',
  }.contains(target)) {
    _unsupported();
  }
  final pp = json.containsKey('pp') ? _integer(json['pp']) : null;
  final maxPp = json.containsKey('maxpp') ? _integer(json['maxpp']) : null;
  if (id != 'struggle' && (pp == null || maxPp == null)) _bad();
  if ((pp == null) != (maxPp == null)) _bad();
  if (maxPp != null && (maxPp == 0 || pp! > maxPp)) _bad();
  return RequestMove(
    slot: slot,
    name: name,
    id: id,
    target: target,
    pp: pp,
    maxPp: maxPp,
    disabled: _flag(json, 'disabled'),
  );
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) _bad();
  return value;
}

List<dynamic> _list(Object? value) {
  if (value is! List) _bad();
  return value;
}

String _text(Object? value, {bool empty = false}) {
  if (value is! String || (!empty && value.trim().isEmpty)) _bad();
  return value;
}

String? _optionalText(
  Map<String, dynamic> json,
  String key, {
  bool empty = false,
}) => json.containsKey(key) ? _text(json[key], empty: empty) : null;
int _integer(Object? value) {
  if (value is! int || value < 0 || value > 9007199254740991) _bad();
  return value;
}

bool _flag(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return false;
  if (json[key] is! bool) _bad();
  return json[key] as bool;
}

String? _typeOrFalse(
  Map<String, dynamic> json,
  String key, {
  bool empty = false,
}) {
  if (!json.containsKey(key) ||
      json[key] == false ||
      (empty && json[key] == '')) {
    return null;
  }
  return _text(json[key]);
}

Never _bad() => throw const FormatException('invalidRequest');
Never _unsupported() => throw UnsupportedError('unsupportedRequest');

void _checkBounds(String text) {
  if (text.length > maxBattleRequestLength) _bad();
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (final unit in text.codeUnits) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        inString = false;
      }
    } else if (unit == 34) {
      inString = true;
    } else if (unit == 123 || unit == 91) {
      if (++depth > maxBattleRequestDepth) _bad();
    } else if (unit == 125 || unit == 93) {
      depth--;
    }
  }
}
