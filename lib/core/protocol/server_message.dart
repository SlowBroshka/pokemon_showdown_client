import 'server_record.dart';
import 'server_record_kind.dart';

export 'server_record.dart';
export 'server_record_kind.dart';

/// Parses one complete WebSocket text message without interpreting its events.
///
/// Room context is local to this call. Unknown event names and all characters
/// after the event type separator are preserved. No JSON or HTML is evaluated.
/// A bare `>` emits a malformed record in global context and resets the room.
/// Empty event names (including `|` and `||text`) remain event records.
/// The returned list is unmodifiable.
List<ServerRecord> parseServerMessage(String message) {
  if (message.isEmpty) {
    return const [];
  }

  final lines = message.split('\n');
  final lineCount = message.endsWith('\n') ? lines.length - 1 : lines.length;
  final records = <ServerRecord>[];
  String? roomId;

  for (var index = 0; index < lineCount; index++) {
    var line = lines[index];
    // Remove CR only as part of CRLF, never from an unterminated line.
    if (index < lines.length - 1 && line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }

    if (line.startsWith('>')) {
      roomId = line.length == 1 ? null : line.substring(1);
      if (roomId == null) {
        records.add(
          ServerRecord(
            roomId: null,
            rawLine: line,
            kind: ServerRecordKind.malformed,
          ),
        );
      }
      continue;
    }

    if (line.startsWith('|')) {
      final separator = line.indexOf('|', 1);
      records.add(
        ServerRecord(
          roomId: roomId,
          rawLine: line,
          kind: ServerRecordKind.event,
          eventType: separator < 0
              ? line.substring(1)
              : line.substring(1, separator),
          data: separator < 0 ? '' : line.substring(separator + 1),
        ),
      );
    } else {
      records.add(
        ServerRecord(
          roomId: roomId,
          rawLine: line,
          kind: line.isEmpty ? ServerRecordKind.empty : ServerRecordKind.text,
        ),
      );
    }
  }

  return List.unmodifiable(records);
}
