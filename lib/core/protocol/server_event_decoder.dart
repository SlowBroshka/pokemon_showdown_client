import 'dart:convert';

import '../matchmaking/search/search_snapshot_decoder.dart';
import 'events/update_search_event.dart';

import '../matchmaking/formats/format_catalog_decoder.dart';
import 'events/formats_event.dart';

import 'battle_event_decoder.dart';

import '../battle/requests/battle_request_decoder.dart';
import 'events/battle_request_event.dart';

import 'events/challenge_event.dart';
import 'events/update_user_event.dart';
import 'events/room_init_event.dart';
import 'events/room_title_event.dart';
import 'events/room_deinit_event.dart';
import 'events/server_error_event.dart';
import 'events/popup_event.dart';
import 'events/name_taken_event.dart';
import 'events/plain_text_event.dart';
import 'events/unknown_server_event.dart';
import 'events/malformed_server_event.dart';
import 'server_event.dart';
import 'server_record.dart';
import 'server_record_kind.dart';

export 'events/challenge_event.dart';
export 'events/update_user_event.dart';
export 'events/room_init_event.dart';
export 'events/room_title_event.dart';
export 'events/room_deinit_event.dart';
export 'events/server_error_event.dart';
export 'events/popup_event.dart';
export 'events/name_taken_event.dart';
export 'events/plain_text_event.dart';
export 'events/unknown_server_event.dart';
export 'events/malformed_server_event.dart';
export 'server_event.dart';
export 'battle_event_decoder.dart';
export 'events/battle_request_event.dart';
export 'events/formats_event.dart';
export 'events/update_search_event.dart';

/// Decodes one record without network access, state changes or rendering.
/// Empty lines return null. Unsupported events and malformed records are explicit
/// results, so a bad record does not prevent decoding subsequent records.
ServerEvent? decodeServerRecord(ServerRecord record) {
  switch (record.kind) {
    case ServerRecordKind.empty:
      return null;
    case ServerRecordKind.text:
      return PlainTextEvent(record, text: record.rawLine);
    case ServerRecordKind.malformed:
      return MalformedServerEvent(record, reason: 'Malformed envelope');
    case ServerRecordKind.event:
      break;
  }

  final type = record.eventType;
  final data = record.data;
  if (type == null || data == null) {
    return MalformedServerEvent(record, reason: 'Missing event type or data');
  }

  final battleEvent = decodeBattleEvent(record);
  if (battleEvent != null) return battleEvent;
  switch (type) {
    case 'updatesearch':
      if (record.roomId != null) {
        return MalformedServerEvent(
          record,
          reason: 'Update search must be global',
        );
      }
      return UpdateSearchEvent(record, result: decodeSearchSnapshot(data));
    case 'formats':
      if (record.roomId != null) {
        return MalformedServerEvent(record, reason: 'Formats must be global');
      }
      return FormatsEvent(record, catalog: decodeFormatCatalog(data));
    case 'request':
      if (record.roomId == null) {
        return MalformedServerEvent(record, reason: 'Request requires a room');
      }
      return BattleRequestEvent(record, request: decodeBattleRequest(data));
    case '':
      return PlainTextEvent(record, text: data);
    case 'challstr':
      if (data.isEmpty) {
        return MalformedServerEvent(record, reason: 'Missing challenge');
      }
      return ChallengeEvent(record, challenge: data);
    case 'updateuser':
      return _decodeUpdateUser(record, data);
    case 'init':
      if (data.isEmpty || data.contains('|')) {
        return MalformedServerEvent(record, reason: 'Invalid room type');
      }
      // Preserve future room types; supported-room policy belongs to the router.
      return RoomInitEvent(record, roomType: data);
    case 'title':
      if (data.isEmpty) {
        return MalformedServerEvent(record, reason: 'Missing room title');
      }
      return RoomTitleEvent(record, title: data);
    case 'deinit':
      if (data.isNotEmpty) {
        return MalformedServerEvent(record, reason: 'Unexpected deinit data');
      }
      return RoomDeinitEvent(record);
    case 'error':
      return ServerErrorEvent(record, message: data);
    case 'popup':
      return PopupEvent(record, message: data);
    case 'nametaken':
      final separator = data.indexOf('|');
      if (separator < 0 || separator == data.length - 1) {
        return MalformedServerEvent(record, reason: 'Missing name or message');
      }
      return NameTakenEvent(
        record,
        username: data.substring(0, separator),
        message: data.substring(separator + 1),
      );
    default:
      return UnknownServerEvent(record, eventType: type, data: data);
  }
}

ServerEvent _decodeUpdateUser(ServerRecord record, String data) {
  final first = data.indexOf('|');
  final second = first < 0 ? -1 : data.indexOf('|', first + 1);
  if (first <= 0 || second < 0) {
    return MalformedServerEvent(record, reason: 'Missing user fields');
  }
  final named = data.substring(first + 1, second);
  if (named != '0' && named != '1') {
    return MalformedServerEvent(record, reason: 'Invalid named flag');
  }
  final third = data.indexOf('|', second + 1);
  final avatar = third < 0
      ? data.substring(second + 1)
      : data.substring(second + 1, third);
  if (avatar.isEmpty) {
    return MalformedServerEvent(record, reason: 'Missing avatar');
  }
  final settings = third < 0 ? null : data.substring(third + 1);
  if (settings != null) {
    try {
      if (jsonDecode(settings) is! Map<String, dynamic>) {
        return MalformedServerEvent(
          record,
          reason: 'Settings must be an object',
        );
      }
    } on FormatException {
      return MalformedServerEvent(record, reason: 'Invalid settings JSON');
    }
  }
  return UpdateUserEvent(
    record,
    user: data.substring(0, first),
    named: named == '1',
    avatar: avatar,
    settingsJson: settings,
  );
}
