import '../battle/state/battle_environment.dart';
import 'battle_events/battle_environment_event.dart';
import 'events/malformed_server_event.dart';
import 'server_event.dart';
import 'server_record.dart';
export 'battle_events/battle_environment_event.dart';

const _operations = {
  '-weather': EnvironmentOperation.weather,
  '-fieldstart': EnvironmentOperation.fieldStart,
  '-fieldend': EnvironmentOperation.fieldEnd,
  '-fieldactivate': EnvironmentOperation.fieldActivate,
  '-sidestart': EnvironmentOperation.sideStart,
  '-sideend': EnvironmentOperation.sideEnd,
  '-swapsideconditions': EnvironmentOperation.swapSides,
};

/// Only the explicitly reviewed Court Change subtype is claimed from -activate.
ServerEvent? decodeBattleEnvironment(ServerRecord record) {
  var operation = _operations[record.eventType];
  if (record.eventType == '-activate') {
    final parts = record.data?.split('|') ?? [];
    if (parts.length < 2 || _id(parts[1]) != 'courtchange') return null;
    operation = EnvironmentOperation.courtChangeActivation;
  }
  if (operation == null) return null;
  try {
    if (record.roomId == null || record.data == null) _bad();
    final all = record.data!.isEmpty ? <String>[] : record.data!.split('|');
    final at = all.indexWhere((s) => s.startsWith('['));
    final parts = at < 0 ? all : all.sublist(0, at);
    final tags = at < 0 ? <String>[] : all.sublist(at);
    String? sourceEffect;
    String? sourceIdent;
    var upkeep = false;
    var silent = false;
    for (final tag in tags) {
      if (tag == '[upkeep]' &&
          operation == EnvironmentOperation.weather &&
          !upkeep) {
        upkeep = true;
      } else if (tag.startsWith('[from] ') && sourceEffect == null) {
        sourceEffect = tag.substring(7);
        if (!RegExp(r'^(move|ability): \S(?:.*\S)?$').hasMatch(sourceEffect)) {
          _bad();
        }
      } else if (tag.startsWith('[of] ') && sourceIdent == null) {
        sourceIdent = tag.substring(5);
        if (!_ident(sourceIdent)) _bad();
      } else if (tag == '[silent]' && !silent) {
        silent = true;
      } else {
        _bad();
      }
    }
    String? condition;
    String? side;
    String? actor;
    switch (operation) {
      case EnvironmentOperation.swapSides:
        if (parts.isNotEmpty || tags.isNotEmpty) _bad();
      case EnvironmentOperation.courtChangeActivation:
        if (parts.length != 2 || tags.isNotEmpty || !_activeIdent(parts[0])) {
          _bad();
        }
        actor = parts[0];
      case EnvironmentOperation.sideStart:
      case EnvironmentOperation.sideEnd:
        if (parts.length != 2 ||
            !RegExp(r'^p[12](?:: \S(?:.*\S)?)?$').hasMatch(parts[0])) {
          _bad();
        }
        side = parts[0].substring(0, 2);
        condition = _id(parts[1]);
        if (!battleSideConditions.containsKey(condition)) _bad();
      case EnvironmentOperation.weather:
        if (parts.length != 1) _bad();
        condition = _id(parts.single);
        if (condition != 'none' && !battleWeather.contains(condition)) _bad();
        if (upkeep &&
            (condition == 'none' ||
                sourceEffect != null ||
                sourceIdent != null)) {
          _bad();
        }
      case EnvironmentOperation.fieldStart:
      case EnvironmentOperation.fieldEnd:
      case EnvironmentOperation.fieldActivate:
        if (parts.length != 1) _bad();
        condition = _id(parts.single);
        if (operation == EnvironmentOperation.fieldActivate) {
          if (!battleFieldActivations.contains(condition)) _bad();
        } else if (!battleTerrains.contains(condition) &&
            !battleFieldConditions.contains(condition)) {
          _bad();
        }
    }
    return BattleEnvironmentEvent(
      record,
      operation: operation,
      condition: condition,
      sideId: side,
      actor: actor,
      upkeep: upkeep,
      sourceEffect: sourceEffect,
      sourceIdent: sourceIdent,
    );
  } on FormatException {
    return MalformedServerEvent(
      record,
      reason: 'Invalid battle environment event',
    );
  }
}

String _id(String value) =>
    (value.startsWith('move: ') ? value.substring(6) : value)
        .toLowerCase()
        .replaceAll(' ', '');
bool _ident(String value) => RegExp(r'^p[12]a?: \S(?:.*\S)?$').hasMatch(value);
bool _activeIdent(String value) =>
    RegExp(r'^p[12]a: \S(?:.*\S)?$').hasMatch(value);
Never _bad() => throw const FormatException('Invalid battle environment event');
