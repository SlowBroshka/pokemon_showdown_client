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
      'One active room · account sign-in\nBattle controls are coming later.';

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

  @override
  String get authHeading => 'Account';

  @override
  String get authDescription =>
      'Use an existing account. Your password is not saved.';

  @override
  String get authUsername => 'Username';

  @override
  String get authPassword => 'Password';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authCancelSignIn => 'Cancel sign-in';

  @override
  String get authSignOut => 'Sign out and disconnect';

  @override
  String get authDisconnected => 'Connect to the server to sign in.';

  @override
  String get authUnavailable => 'Sign-in is unavailable for this server.';

  @override
  String get authWaitingChallenge =>
      'Waiting for sign-in details from the server…';

  @override
  String get authReady => 'Ready to sign in to your account.';

  @override
  String get authAuthenticating => 'Checking account credentials…';

  @override
  String get authAwaitingConfirmation =>
      'Waiting for the game server to confirm sign-in…';

  @override
  String authSignedIn(String username) {
    return 'Signed in as $username';
  }

  @override
  String get authDisconnecting => 'Disconnecting…';

  @override
  String get authDisposed => 'The session has ended.';

  @override
  String get authInvalidInput =>
      'Check your username and password. Use a name of up to 18 characters with Latin letters or digits.';

  @override
  String get authNetwork =>
      'Could not reach the sign-in service. Please try again.';

  @override
  String get authTimeout => 'Sign-in timed out. Please try again.';

  @override
  String get authCancelled => 'Sign-in cancelled.';

  @override
  String get authUnexpectedRedirect =>
      'The sign-in service returned an unexpected redirect. Sign-in stopped.';

  @override
  String get authRateLimited =>
      'Too many sign-in attempts. Wait before trying again.';

  @override
  String get authServiceUnavailable =>
      'The sign-in service is temporarily unavailable.';

  @override
  String get authHttpFailure =>
      'The sign-in service could not process the request.';

  @override
  String get authInvalidResponse =>
      'The sign-in service returned an unsupported response.';

  @override
  String get authResponseTooLarge =>
      'The sign-in response exceeded the allowed size.';

  @override
  String get authLoginRejected =>
      'Sign-in was rejected. Check your account details and try again.';

  @override
  String get authInvalidAssertion =>
      'The sign-in service returned invalid confirmation data.';

  @override
  String get authUnsupportedServer =>
      'Account sign-in currently supports only the default Pokémon Showdown server.';

  @override
  String get authChallengeTimeout =>
      'The server did not provide sign-in details. Please reconnect.';

  @override
  String get authConfirmationTimeout =>
      'The game server did not confirm sign-in. Please reconnect.';

  @override
  String get authIdentityRejected =>
      'The game server did not confirm your account. Please reconnect.';

  @override
  String get authConnectionLost =>
      'The connection was lost. Reconnect and sign in again.';

  @override
  String get authSendFailed => 'Could not complete sign-in. Please reconnect.';

  @override
  String get authInvalidServerEvent =>
      'The server sent invalid sign-in data. Please reconnect.';
}
