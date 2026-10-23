import 'server_record.dart';

/// Decoded server data. The source may contain private information: do not log it.
abstract class ServerEvent {
  const ServerEvent(this.record);

  final ServerRecord record;
  String? get roomId => record.roomId;
}
