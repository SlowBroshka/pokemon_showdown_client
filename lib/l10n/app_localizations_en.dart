// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get connectionTimeout => 'Connection timed out.';

  @override
  String get serverClosed => 'The server closed the connection.';

  @override
  String get unsupportedMessage => 'The server sent an unsupported message.';

  @override
  String get sendFailed => 'Could not send the command.';

  @override
  String get connectionFailed => 'Connection error. Please reconnect.';

  @override
  String get invalidWssAddress =>
      'Enter a WSS address without credentials or a fragment.';

  @override
  String get invalidAddress => 'Invalid server address.';

  @override
  String get connectionUnavailable => 'Connection is currently unavailable.';

  @override
  String get invalidRoomId =>
      'Room ID: lowercase Latin letters, digits and hyphens.';

  @override
  String get roomTimeout =>
      'The server did not confirm the action. Connection closed; please reconnect.';

  @override
  String get notConnected => 'Not connected to the server.';

  @override
  String get connecting => 'Connecting…';

  @override
  String get connected => 'Connection established.';

  @override
  String get disconnected => 'Connection closed.';

  @override
  String get roomJoined => 'Joined the room.';

  @override
  String get roomLeft => 'Left the room.';

  @override
  String get serverNotice =>
      'The server rejected the action or sent a notification. You may need to sign in.';

  @override
  String get appTitle => 'Pokémon Showdown';

  @override
  String get connectionHeading => 'Connection';

  @override
  String get connectionDescription =>
      'Test screen · one active room\nSign-in and battle controls are coming later.';

  @override
  String get serverAddress => 'Server address (WSS)';

  @override
  String get statusConnecting => 'Status: connecting…';

  @override
  String get statusConnected => 'Status: connected';

  @override
  String get statusDisconnected => 'Status: disconnected';

  @override
  String get connect => 'Connect';

  @override
  String get cancel => 'Cancel';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get roomHeading => 'Room';

  @override
  String get roomIdLabel => 'Room ID';

  @override
  String get roomIdHint => 'For example, lobby';

  @override
  String get join => 'Join';

  @override
  String get awaitingJoin => 'Waiting for join confirmation…';

  @override
  String get noActiveRoom => 'No active room.';

  @override
  String get staleRoom =>
      'Data is outdated. Reconnect and join the room again.';

  @override
  String get awaitingLeave => 'Waiting for leave confirmation…';

  @override
  String get leaveRoom => 'Leave room';

  @override
  String get noticesHeading => 'Notifications';

  @override
  String get noNotices => 'No notifications yet.';

  @override
  String roomIdValue(String roomId) {
    return 'ID: $roomId';
  }

  @override
  String roomType(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'chat': 'chat',
      'battle': 'battle',
      'other': 'other',
    });
    return 'Type: $_temp0';
  }
}
