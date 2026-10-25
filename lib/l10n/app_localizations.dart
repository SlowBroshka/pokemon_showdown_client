import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Connection screen: connection timeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out.'**
  String get connectionTimeout;

  /// Connection screen: server closed.
  ///
  /// In en, this message translates to:
  /// **'The server closed the connection.'**
  String get serverClosed;

  /// Connection screen: unsupported message.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unsupported message.'**
  String get unsupportedMessage;

  /// Connection screen: send failed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the command.'**
  String get sendFailed;

  /// Connection screen: connection failed.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please reconnect.'**
  String get connectionFailed;

  /// Connection screen: invalid wss address.
  ///
  /// In en, this message translates to:
  /// **'Enter a WSS address without credentials or a fragment.'**
  String get invalidWssAddress;

  /// Connection screen: invalid address.
  ///
  /// In en, this message translates to:
  /// **'Invalid server address.'**
  String get invalidAddress;

  /// Connection screen: connection unavailable.
  ///
  /// In en, this message translates to:
  /// **'Connection is currently unavailable.'**
  String get connectionUnavailable;

  /// Connection screen: invalid room id.
  ///
  /// In en, this message translates to:
  /// **'Room ID: lowercase Latin letters, digits and hyphens.'**
  String get invalidRoomId;

  /// Connection screen: room timeout.
  ///
  /// In en, this message translates to:
  /// **'The server did not confirm the action. Connection closed; please reconnect.'**
  String get roomTimeout;

  /// Connection screen: not connected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to the server.'**
  String get notConnected;

  /// Connection screen: connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// Connection screen: connected.
  ///
  /// In en, this message translates to:
  /// **'Connection established.'**
  String get connected;

  /// Connection screen: disconnected.
  ///
  /// In en, this message translates to:
  /// **'Connection closed.'**
  String get disconnected;

  /// Connection screen: room joined.
  ///
  /// In en, this message translates to:
  /// **'Joined the room.'**
  String get roomJoined;

  /// Connection screen: room left.
  ///
  /// In en, this message translates to:
  /// **'Left the room.'**
  String get roomLeft;

  /// Connection screen: server notice.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the action or sent a notification. You may need to sign in.'**
  String get serverNotice;

  /// Connection screen: app title.
  ///
  /// In en, this message translates to:
  /// **'Pokémon Showdown'**
  String get appTitle;

  /// Connection screen: connection heading.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionHeading;

  /// Connection screen: connection description.
  ///
  /// In en, this message translates to:
  /// **'One active room · account sign-in\nBattle controls are coming later.'**
  String get connectionDescription;

  /// Connection screen: server address.
  ///
  /// In en, this message translates to:
  /// **'Server address (WSS)'**
  String get serverAddress;

  /// Connection screen: status connecting.
  ///
  /// In en, this message translates to:
  /// **'Status: connecting…'**
  String get statusConnecting;

  /// Connection screen: status connected.
  ///
  /// In en, this message translates to:
  /// **'Status: connected'**
  String get statusConnected;

  /// Connection screen: status disconnected.
  ///
  /// In en, this message translates to:
  /// **'Status: disconnected'**
  String get statusDisconnected;

  /// Connection screen: connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Connection screen: cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Connection screen: disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// Connection screen: room heading.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get roomHeading;

  /// Connection screen: room id label.
  ///
  /// In en, this message translates to:
  /// **'Room ID'**
  String get roomIdLabel;

  /// Connection screen: room id hint.
  ///
  /// In en, this message translates to:
  /// **'For example, lobby'**
  String get roomIdHint;

  /// Connection screen: join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// Connection screen: awaiting join.
  ///
  /// In en, this message translates to:
  /// **'Waiting for join confirmation…'**
  String get awaitingJoin;

  /// Connection screen: no active room.
  ///
  /// In en, this message translates to:
  /// **'No active room.'**
  String get noActiveRoom;

  /// Connection screen: stale room.
  ///
  /// In en, this message translates to:
  /// **'Data is outdated. Reconnect and join the room again.'**
  String get staleRoom;

  /// Connection screen: awaiting leave.
  ///
  /// In en, this message translates to:
  /// **'Waiting for leave confirmation…'**
  String get awaitingLeave;

  /// Connection screen: leave room.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get leaveRoom;

  /// Connection screen: notices heading.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get noticesHeading;

  /// Connection screen: no notices.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get noNotices;

  /// Connection screen: room id value.
  ///
  /// In en, this message translates to:
  /// **'ID: {roomId}'**
  String roomIdValue(String roomId);

  /// Connection screen: room type.
  ///
  /// In en, this message translates to:
  /// **'Type: {type, select, chat{chat} battle{battle} other{other}}'**
  String roomType(String type);

  /// Account sign-in: Account
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get authHeading;

  /// Account sign-in: Use an existing account. Your password is not saved.
  ///
  /// In en, this message translates to:
  /// **'Use an existing account. Your password is not saved.'**
  String get authDescription;

  /// Account sign-in: Username
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// Account sign-in: Password
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// Account sign-in: Show password
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// Account sign-in: Hide password
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// Account sign-in: Sign in
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// Account sign-in: Cancel sign-in
  ///
  /// In en, this message translates to:
  /// **'Cancel sign-in'**
  String get authCancelSignIn;

  /// Account sign-in: Sign out and disconnect
  ///
  /// In en, this message translates to:
  /// **'Sign out and disconnect'**
  String get authSignOut;

  /// Account sign-in: Connect to the server to sign in.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server to sign in.'**
  String get authDisconnected;

  /// Account sign-in: Sign-in is unavailable for this server.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is unavailable for this server.'**
  String get authUnavailable;

  /// Account sign-in: Waiting for sign-in details from the server…
  ///
  /// In en, this message translates to:
  /// **'Waiting for sign-in details from the server…'**
  String get authWaitingChallenge;

  /// Account sign-in: Ready to sign in to your account.
  ///
  /// In en, this message translates to:
  /// **'Ready to sign in to your account.'**
  String get authReady;

  /// Account sign-in: Checking account credentials…
  ///
  /// In en, this message translates to:
  /// **'Checking account credentials…'**
  String get authAuthenticating;

  /// Account sign-in: Waiting for the game server to confirm sign-in…
  ///
  /// In en, this message translates to:
  /// **'Waiting for the game server to confirm sign-in…'**
  String get authAwaitingConfirmation;

  /// Account sign-in: Signed in as {username}
  ///
  /// In en, this message translates to:
  /// **'Signed in as {username}'**
  String authSignedIn(String username);

  /// Account sign-in: Disconnecting…
  ///
  /// In en, this message translates to:
  /// **'Disconnecting…'**
  String get authDisconnecting;

  /// Account sign-in: The session has ended.
  ///
  /// In en, this message translates to:
  /// **'The session has ended.'**
  String get authDisposed;

  /// Account sign-in: Check your username and password. Use a name of up to 18 ASCII characters.
  ///
  /// In en, this message translates to:
  /// **'Check your username and password. Use a name of up to 18 characters with Latin letters or digits.'**
  String get authInvalidInput;

  /// Account sign-in: Could not reach the sign-in service. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the sign-in service. Please try again.'**
  String get authNetwork;

  /// Account sign-in: Sign-in timed out. Please try again.
  ///
  /// In en, this message translates to:
  /// **'Sign-in timed out. Please try again.'**
  String get authTimeout;

  /// Account sign-in: Sign-in cancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in cancelled.'**
  String get authCancelled;

  /// Account sign-in: The sign-in service returned an unexpected redirect. Sign-in stopped.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service returned an unexpected redirect. Sign-in stopped.'**
  String get authUnexpectedRedirect;

  /// Account sign-in: Too many sign-in attempts. Wait before trying again.
  ///
  /// In en, this message translates to:
  /// **'Too many sign-in attempts. Wait before trying again.'**
  String get authRateLimited;

  /// Account sign-in: The sign-in service is temporarily unavailable.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service is temporarily unavailable.'**
  String get authServiceUnavailable;

  /// Account sign-in: The sign-in service could not process the request.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service could not process the request.'**
  String get authHttpFailure;

  /// Account sign-in: The sign-in service returned an unsupported response.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service returned an unsupported response.'**
  String get authInvalidResponse;

  /// Account sign-in: The sign-in response exceeded the allowed size.
  ///
  /// In en, this message translates to:
  /// **'The sign-in response exceeded the allowed size.'**
  String get authResponseTooLarge;

  /// Account sign-in: Sign-in was rejected. Check your account details and try again.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was rejected. Check your account details and try again.'**
  String get authLoginRejected;

  /// Account sign-in: The sign-in service returned invalid confirmation data.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service returned invalid confirmation data.'**
  String get authInvalidAssertion;

  /// Account sign-in: Account sign-in currently supports only the default Pokémon Showdown server.
  ///
  /// In en, this message translates to:
  /// **'Account sign-in currently supports only the default Pokémon Showdown server.'**
  String get authUnsupportedServer;

  /// Account sign-in: The server did not provide sign-in details. Please reconnect.
  ///
  /// In en, this message translates to:
  /// **'The server did not provide sign-in details. Please reconnect.'**
  String get authChallengeTimeout;

  /// Account sign-in: The game server did not confirm sign-in. Please reconnect.
  ///
  /// In en, this message translates to:
  /// **'The game server did not confirm sign-in. Please reconnect.'**
  String get authConfirmationTimeout;

  /// Account sign-in: The game server did not confirm your account. Please reconnect.
  ///
  /// In en, this message translates to:
  /// **'The game server did not confirm your account. Please reconnect.'**
  String get authIdentityRejected;

  /// Account sign-in: The connection was lost. Reconnect and sign in again.
  ///
  /// In en, this message translates to:
  /// **'The connection was lost. Reconnect and sign in again.'**
  String get authConnectionLost;

  /// Account sign-in: Could not complete sign-in. Please reconnect.
  ///
  /// In en, this message translates to:
  /// **'Could not complete sign-in. Please reconnect.'**
  String get authSendFailed;

  /// Account sign-in: The server sent invalid sign-in data. Please reconnect.
  ///
  /// In en, this message translates to:
  /// **'The server sent invalid sign-in data. Please reconnect.'**
  String get authInvalidServerEvent;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
