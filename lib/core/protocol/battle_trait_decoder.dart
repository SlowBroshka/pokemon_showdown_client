import '../battle/state/effect_observation.dart';
import '../battle/state/pokemon_traits.dart';
import 'battle_events/battle_trait_event.dart';
import 'events/malformed_server_event.dart';
import 'server_event.dart';
import 'server_record.dart';
export 'battle_events/battle_trait_event.dart';

const _transfers = {
  'move: Covet',
  'move: Thief',
  'move: Bestow',
  'ability: Magician',
  'ability: Pickpocket',
};
const _itemSources = {
  ..._transfers,
  'move: Trick',
  'move: Switcheroo',
  'move: Recycle',
  'ability: Harvest',
  'ability: Pickup',
  'ability: Frisk',
};
const _removals = {
  'move: Knock Off',
  'move: Corrosive Gas',
  'move: Incinerate',
  'move: Fling',
};
const _abilityChanges = {
  'ability: Trace',
  'move: Role Play',
  'move: Entrainment',
  'move: Worry Seed',
  'move: Simple Beam',
};
const simpleAbilityActivations = {
  'Emergency Exit',
  'Guard Dog',
  'Hadron Engine',
  'Healer',
  'Hydration',
  'Immunity',
  'Insomnia',
  'Lightning Rod',
  'Limber',
  'Magma Armor',
  'Oblivious',
  'Orichalcum Pulse',
  'Own Tempo',
  'Pastel Veil',
  'Quick Draw',
  'Ripen',
  'Screen Cleaner',
  'Shed Skin',
  'Sticky Hold',
  'Storm Drain',
  'Suction Cups',
  'Synchronize',
  'Telepathy',
  'Thermal Exchange',
  'Toxic Debris',
  'Vital Spirit',
  'Water Bubble',
  'Water Veil',
  'Wimp Out',
};
const _blockAbilities = {
  'Aroma Veil',
  'Flower Veil',
  'Pastel Veil',
  'Sweet Veil',
};

ServerEvent? decodeBattleTrait(ServerRecord record) {
  final type = record.eventType;
  if (!{
    '-item',
    '-enditem',
    '-ability',
    '-endability',
    '-activate',
    '-block',
    '-immune',
  }.contains(type)) {
    return null;
  }
  if (type == '-immune' && !(record.data?.contains('[from]') ?? false)) {
    return null;
  }
  // PR4 owns this subtype and retains its exact validation.
  if (type == '-activate' &&
      record.data?.split('|').elementAtOrNull(1) == 'move: Court Change') {
    return null;
  }
  try {
    if (record.roomId == null || record.data == null) _bad();
    final all = record.data!.split('|');
    final at = all.indexWhere((v) => v.startsWith('['));
    final p = at < 0 ? all : all.sublist(0, at);
    final tags = at < 0 ? <String>[] : all.sublist(at);
    final parsed = _tags(tags);
    final from = parsed['from'];
    final other = parsed['of'];
    if (p.isEmpty || !publicActiveIdent(p[0])) _bad();
    final actor = p[0];
    PublicEffectSource? source = from == null
        ? null
        : parseEffectSource(from, other);
    TraitOperation op;
    String? name;
    String? previous;
    String? otherAbility;
    ItemEndReason? reason;
    switch (type) {
      case '-immune':
        _count(p, 1);
        _allow(parsed, {'from', 'of', 'msg'});
        if (source == null) _bad();
        op = TraitOperation.notice;

      case '-item':
        _count(p, 2);
        name = _name(p[1]);
        op = TraitOperation.item;
        _allow(parsed, {'from', 'of', 'silent'});
        if (from != null && !_itemSources.contains(from)) _bad();
        if ((_transfers.contains(from) || from == 'ability: Frisk') &&
            other == null) {
          _bad();
        }
      case '-enditem':
        _count(p, 2);
        name = _name(p[1]);
        op = TraitOperation.endItem;
        _allow(parsed, {'from', 'of', 'silent', 'eat', 'weaken', 'move'});
        if (from != null &&
            !_transfers.contains(from) &&
            from != 'move: Trick' &&
            from != 'move: Switcheroo' &&
            !_removals.contains(from) &&
            from != 'gem' &&
            from != 'stealeat') {
          _bad();
        }
        if (parsed.containsKey('eat') &&
            (from != null || parsed.containsKey('weaken'))) {
          _bad();
        }
        reason =
            parsed.containsKey('eat') ||
                parsed.containsKey('weaken') ||
                from == 'gem' ||
                from == 'stealeat'
            ? ItemEndReason.consumed
            : _transfers.contains(from) ||
                  from == 'move: Trick' ||
                  from == 'move: Switcheroo'
            ? ItemEndReason.transferred
            : _removals.contains(from)
            ? ItemEndReason.removed
            : ItemEndReason.ended;
      case '-ability':
        if (p.length != 2 && p.length != 3) _bad();
        name = _ability(p[1]);
        op = TraitOperation.ability;
        _allow(parsed, {'from', 'of', 'silent'});
        if (from != null && !_abilityChanges.contains(from)) _bad();
        if (p.length == 3) {
          if (p[2] == 'boost') {
            if (name != 'Intimidate' || from != null) _bad();
          } else {
            if (from == null) _bad();
            previous = _ability(p[2]);
          }
        }
      case '-endability':
        // Gen9 Gastro Acid emits the actor only; no invented ability name.
        _count(p, 1);
        _allow(parsed, {'silent'});
        op = TraitOperation.suppressAbility;
      case '-activate':
      case '-block':
        if (p.length < 2) _bad();
        op = type == '-block' ? TraitOperation.block : TraitOperation.activate;
        final effect = p[1];
        if (type == '-activate' &&
            (effect == 'Skill Swap' || effect == 'move: Skill Swap')) {
          _count(p, 4);
          _allow(parsed, {'of'});
          if (other == null) _bad();
          name = _ability(p[2]);
          otherAbility = _ability(p[3]);
          source = PublicEffectSource(
            kind: EffectSourceKind.move,
            name: 'Skill Swap',
            ofIdent: other,
          );
          op = TraitOperation.skillSwap;
        } else {
          _count(p, 2);
          source = parseEffectSource(effect, other);
          name = source.name;
          if (type == '-block') {
            _allow(parsed, {'of'});
            if (!(source.kind == EffectSourceKind.item &&
                    name == 'Ability Shield') &&
                !(source.kind == EffectSourceKind.ability &&
                    _blockAbilities.contains(name))) {
              _bad();
            }
          } else if (effect == 'move: Substitute') {
            _allow(parsed, {'damage'});
            if (!parsed.containsKey('damage')) _bad();
          } else if (effect == 'move: Trick' || effect == 'move: Switcheroo') {
            _allow(parsed, {'of'});
            if (other == null) _bad();
          } else if (source.kind == EffectSourceKind.ability &&
              simpleAbilityActivations.contains(name)) {
            _allow(parsed, {'silent'});
          } else if (effect == 'item: Quick Claw') {
            _allow(parsed, {});
          } else {
            return null;
          }
        }
      default:
        return null;
    }
    if (other != null && !publicActiveIdent(other)) _bad();
    return BattleTraitEvent(
      record,
      operation: op,
      actor: actor,
      name: name,
      previous: previous,
      other: other,
      otherAbility: otherAbility,
      source: source,
      itemEndReason: reason,
    );
  } on FormatException {
    return MalformedServerEvent(record, reason: 'Invalid public trait event');
  }
}

/// Preserve source annotations only on reviewed public event families. The inner
/// decoder remains responsible for event payloads and all state semantics.
ServerEvent attributeBattleEvent(ServerEvent event) {
  if (event is MalformedServerEvent) return event;
  if (!{
    '-damage',
    '-heal',
    '-sethp',
    '-status',
    '-curestatus',
    '-boost',
    '-unboost',
    '-setboost',
    '-clearboost',
    '-clearnegativeboost',
    '-clearpositiveboost',
    '-copyboost',
    '-swapboost',
    '-invertboost',
    '-weather',
    '-fieldstart',
    '-fieldend',
    '-sidestart',
    '-sideend',
    '-immune',
  }.contains(event.record.eventType)) {
    return event;
  }
  final tags = event.record.data!
      .split('|')
      .where((v) => v.startsWith('['))
      .toList();
  final from = tags.where((v) => v.startsWith('[from]')).toList();
  if (from.isEmpty) return event;
  try {
    final of = tags.where((v) => v.startsWith('[of]')).toList();
    if (from.length != 1 ||
        of.length > 1 ||
        !from.single.startsWith('[from] ')) {
      _bad();
    }
    String? ofIdent;
    if (of.isNotEmpty) {
      if (!of.single.startsWith('[of] ')) _bad();
      ofIdent = of.single.substring(5);
      if (!publicIdent(ofIdent)) _bad();
    }
    return BattleAttributedEvent(
      event,
      parseEffectSource(from.single.substring(7), ofIdent),
    );
  } on FormatException {
    return MalformedServerEvent(event.record, reason: 'Invalid effect source');
  }
}

PublicEffectSource parseEffectSource(String value, String? ofIdent) {
  for (final kind in [
    EffectSourceKind.item,
    EffectSourceKind.ability,
    EffectSourceKind.move,
  ]) {
    final prefix = '${kind.name}: ';
    if (value.startsWith(prefix)) {
      return PublicEffectSource(
        kind: kind,
        name: _name(value.substring(prefix.length)),
        ofIdent: ofIdent,
      );
    }
  }
  return PublicEffectSource(
    kind: EffectSourceKind.condition,
    name: _name(value),
    ofIdent: ofIdent,
  );
}

Map<String, String> _tags(List<String> tags) {
  final result = <String, String>{};
  for (final tag in tags) {
    final match = RegExp(r'^\[([a-z]+)\](?: (.+))?$').firstMatch(tag);
    if (match == null) _bad();
    final key = match.group(1)!;
    if (result.containsKey(key)) _bad();
    final value = match.group(2) ?? '';
    if ({'from', 'of', 'move'}.contains(key)) {
      if (value.isEmpty) _bad();
    } else if (value.isNotEmpty) {
      _bad();
    }
    result[key] = value;
  }
  return result;
}

void _allow(Map<String, String> tags, Set<String> allowed) {
  if (tags.keys.any((k) => !allowed.contains(k))) _bad();
}

void _count(List<String> parts, int count) {
  if (parts.length != count) _bad();
}

String _name(String value) {
  if (value.length > 100 ||
      !RegExp(r"^[A-Za-z0-9][A-Za-z0-9 '’:.%\-]*[A-Za-z0-9.)%]$|^[A-Za-z0-9]$")
          .hasMatch(value)) {
    _bad();
  }
  return value;
}

String _ability(String value) {
  _name(value);
  if ({
    'As One',
    'As One (Glastrier)',
    'As One (Spectrier)',
    'Neutralizing Gas',
    'No Ability',
  }.contains(value)) {
    _bad();
  }
  return value;
}

bool publicActiveIdent(String value) =>
    value.length <= 120 && RegExp(r'^p[12]a: \S(?:.*\S)?$').hasMatch(value);
bool publicIdent(String value) =>
    value.length <= 120 && RegExp(r'^p[12]a?: \S(?:.*\S)?$').hasMatch(value);
Never _bad() => throw const FormatException('Invalid trait event');
