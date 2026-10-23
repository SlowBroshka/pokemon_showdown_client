import 'server_record_kind.dart';

/// An immutable line, excluding its LF or CRLF terminator.
///
/// Valid room headers update context and do not produce records. A null
/// [roomId] denotes global context. Only event records have [eventType] and
/// [data]; an event without a data separator has an empty data string.
final class ServerRecord {
  const ServerRecord({
    required this.roomId,
    required this.rawLine,
    required this.kind,
    this.eventType,
    this.data,
  });

  final String? roomId;
  final String rawLine;
  final ServerRecordKind kind;
  final String? eventType;
  final String? data;
}
