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
  /// **'One active room · account sign-in · battle prototype'**
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

  /// Battle panel: battleHeading
  ///
  /// In en, this message translates to:
  /// **'Battle'**
  String get battleHeading;

  /// Battle panel: battleScope
  ///
  /// In en, this message translates to:
  /// **'Prototype: Gen 9 singles. Unsupported mechanics disable choices.'**
  String get battleScope;

  /// Battle panel: battleTurn
  ///
  /// In en, this message translates to:
  /// **'Turn {turn}'**
  String battleTurn(int turn);

  /// Battle panel: battlePublicField
  ///
  /// In en, this message translates to:
  /// **'Active Pokémon · public observations'**
  String get battlePublicField;

  /// Battle panel: battleUnknown
  ///
  /// In en, this message translates to:
  /// **'Not revealed'**
  String get battleUnknown;

  /// Battle panel: battlePublicHp
  ///
  /// In en, this message translates to:
  /// **'Reported HP: {hp}/{maximum}'**
  String battlePublicHp(int hp, String maximum);

  /// Battle panel: battlePrivateHp
  ///
  /// In en, this message translates to:
  /// **'HP: {hp}/{maximum}'**
  String battlePrivateHp(int hp, String maximum);

  /// Battle panel: battleFainted
  ///
  /// In en, this message translates to:
  /// **'Fainted'**
  String get battleFainted;

  /// Battle panel: battleStatus
  ///
  /// In en, this message translates to:
  /// **'Status: {status, select, brn{burn} par{paralysis} psn{poison} tox{bad poison} slp{sleep} frz{freeze} other{none}}'**
  String battleStatus(String status);

  /// Battle panel: battleTeraType
  ///
  /// In en, this message translates to:
  /// **'Tera: {type}'**
  String battleTeraType(String type);

  /// Battle panel: battleTeam
  ///
  /// In en, this message translates to:
  /// **'Your team · last private snapshot'**
  String get battleTeam;

  /// Battle panel: battleActive
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get battleActive;

  /// Battle panel: battleMoves
  ///
  /// In en, this message translates to:
  /// **'Choose a move'**
  String get battleMoves;

  /// Battle panel: battlePp
  ///
  /// In en, this message translates to:
  /// **'PP: {current}/{maximum}'**
  String battlePp(int current, String maximum);

  /// Battle panel: battleMove
  ///
  /// In en, this message translates to:
  /// **'{slot}. {name}'**
  String battleMove(int slot, String name);

  /// Battle panel: battleSwitch
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String battleSwitch(String name);

  /// Battle panel: battleTera
  ///
  /// In en, this message translates to:
  /// **'Terastallize with this move'**
  String get battleTera;

  /// Battle panel: battleReady
  ///
  /// In en, this message translates to:
  /// **'Choose a move or an available replacement.'**
  String get battleReady;

  /// Battle panel: battleForced
  ///
  /// In en, this message translates to:
  /// **'Choose a replacement.'**
  String get battleForced;

  /// Battle panel: battleWaiting
  ///
  /// In en, this message translates to:
  /// **'Waiting for the next decision…'**
  String get battleWaiting;

  /// Battle panel: battleSubmitted
  ///
  /// In en, this message translates to:
  /// **'Choice sent. Waiting for the server…'**
  String get battleSubmitted;

  /// Battle panel: battleUncertain
  ///
  /// In en, this message translates to:
  /// **'The outcome of sending is unknown. Waiting for a new request; no automatic retry.'**
  String get battleUncertain;

  /// Battle panel: battleUnavailable
  ///
  /// In en, this message translates to:
  /// **'Choice unavailable. Waiting for updated choices from the server.'**
  String get battleUnavailable;

  /// Battle panel: battleRejected
  ///
  /// In en, this message translates to:
  /// **'The server rejected the choice. You can choose again.'**
  String get battleRejected;

  /// Battle panel: battleUnsupported
  ///
  /// In en, this message translates to:
  /// **'This battle state is not supported. Choices are disabled.'**
  String get battleUnsupported;

  /// Battle panel: battleMalformed
  ///
  /// In en, this message translates to:
  /// **'The server sent an unreadable decision request. Waiting for an update.'**
  String get battleMalformed;

  /// Battle panel: battleStopped
  ///
  /// In en, this message translates to:
  /// **'Choices are disabled for this room.'**
  String get battleStopped;

  /// Battle panel: battleClosed
  ///
  /// In en, this message translates to:
  /// **'The room is closed. No result was reported.'**
  String get battleClosed;

  /// Battle panel: battleWinner
  ///
  /// In en, this message translates to:
  /// **'Winner: {name}'**
  String battleWinner(String name);

  /// Battle panel: battleTie
  ///
  /// In en, this message translates to:
  /// **'The battle ended in a tie.'**
  String get battleTie;

  /// Battle panel: battleLog
  ///
  /// In en, this message translates to:
  /// **'Recent actions'**
  String get battleLog;

  /// Battle panel: battleLogMove
  ///
  /// In en, this message translates to:
  /// **'Turn {turn}: {actor} used {action}.'**
  String battleLogMove(int turn, String actor, String action);

  /// Battle panel: battleLogCant
  ///
  /// In en, this message translates to:
  /// **'Turn {turn}: {actor} could not act ({action}).'**
  String battleLogCant(int turn, String actor, String action);

  /// Battle panel: battleLogEmpty
  ///
  /// In en, this message translates to:
  /// **'No actions yet.'**
  String get battleLogEmpty;

  /// Matchmaking panel: Heading.
  ///
  /// In en, this message translates to:
  /// **'Find a battle'**
  String get matchmakingHeading;

  /// Matchmaking panel: Format.
  ///
  /// In en, this message translates to:
  /// **'Gen 9 Random Battle'**
  String get matchmakingFormat;

  /// Matchmaking panel: Experimental.
  ///
  /// In en, this message translates to:
  /// **'Enable experimental battles'**
  String get matchmakingExperimental;

  /// Matchmaking panel: ExperimentalHint.
  ///
  /// In en, this message translates to:
  /// **'Some battle mechanics are not supported yet. You may be unable to make a move.'**
  String get matchmakingExperimentalHint;

  /// Matchmaking panel: RatedHint.
  ///
  /// In en, this message translates to:
  /// **'Rated search; the server may disable rating changes.'**
  String get matchmakingRatedHint;

  /// Matchmaking panel: AccountHint.
  ///
  /// In en, this message translates to:
  /// **'Cancelling affects this format in other clients signed in to the same account too.'**
  String get matchmakingAccountHint;

  /// Matchmaking panel: Start.
  ///
  /// In en, this message translates to:
  /// **'Find opponent'**
  String get matchmakingStart;

  /// Matchmaking panel: Cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel search'**
  String get matchmakingCancel;

  /// Matchmaking panel: Recover.
  ///
  /// In en, this message translates to:
  /// **'Disconnect to recover'**
  String get matchmakingRecover;

  /// Matchmaking panel: RecoveryHint.
  ///
  /// In en, this message translates to:
  /// **'Disconnect, then reconnect and sign in to check the account again. Disconnecting does not cancel a search on the server.'**
  String get matchmakingRecoveryHint;

  /// Matchmaking panel: Unavailable.
  ///
  /// In en, this message translates to:
  /// **'Search is not available yet.'**
  String get matchmakingUnavailable;

  /// Matchmaking panel: Idle.
  ///
  /// In en, this message translates to:
  /// **'Ready to find an opponent.'**
  String get matchmakingIdle;

  /// Matchmaking panel: Submitting.
  ///
  /// In en, this message translates to:
  /// **'Starting search; waiting for the server.'**
  String get matchmakingSubmitting;

  /// Matchmaking panel: Searching.
  ///
  /// In en, this message translates to:
  /// **'Looking for an opponent…'**
  String get matchmakingSearching;

  /// Matchmaking panel: Cancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancellation requested; waiting for the outcome.'**
  String get matchmakingCancelling;

  /// Matchmaking panel: StoppedObserved.
  ///
  /// In en, this message translates to:
  /// **'No search in the latest update. Checking whether a battle is being created.'**
  String get matchmakingStoppedObserved;

  /// Matchmaking panel: AwaitingBattle.
  ///
  /// In en, this message translates to:
  /// **'A possible battle was found. Waiting for confirmation.'**
  String get matchmakingAwaitingBattle;

  /// Matchmaking panel: InBattle.
  ///
  /// In en, this message translates to:
  /// **'Battle found. Your battle is shown below.'**
  String get matchmakingInBattle;

  /// Matchmaking panel: OutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'The search outcome is unknown. Starting another search is blocked.'**
  String get matchmakingOutcomeUnknown;

  /// Matchmaking panel: Disconnected.
  ///
  /// In en, this message translates to:
  /// **'Connect to a server to search.'**
  String get matchmakingDisconnected;

  /// Matchmaking panel: NeedAccount.
  ///
  /// In en, this message translates to:
  /// **'Sign in to an existing account above.'**
  String get matchmakingNeedAccount;

  /// Matchmaking panel: NeedExperimental.
  ///
  /// In en, this message translates to:
  /// **'Enable experimental battles to continue.'**
  String get matchmakingNeedExperimental;

  /// Matchmaking panel: NeedData.
  ///
  /// In en, this message translates to:
  /// **'Waiting for up-to-date account and server information.'**
  String get matchmakingNeedData;

  /// Matchmaking panel: RoomBusy.
  ///
  /// In en, this message translates to:
  /// **'Finish the current room operation before searching.'**
  String get matchmakingRoomBusy;

  /// Matchmaking panel: ExternalSearch.
  ///
  /// In en, this message translates to:
  /// **'This account already has a search. Check your other clients.'**
  String get matchmakingExternalSearch;

  /// Matchmaking panel: ExistingGame.
  ///
  /// In en, this message translates to:
  /// **'This account already has a game. Finish it before searching.'**
  String get matchmakingExistingGame;

  /// Matchmaking panel: MalformedCatalog.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unreadable format list. Search is unavailable.'**
  String get matchmakingMalformedCatalog;

  /// Matchmaking panel: LegacyCatalog.
  ///
  /// In en, this message translates to:
  /// **'This server uses an unsupported format list.'**
  String get matchmakingLegacyCatalog;

  /// Matchmaking panel: NotAdvertised.
  ///
  /// In en, this message translates to:
  /// **'This server does not offer Gen 9 Random Battle.'**
  String get matchmakingNotAdvertised;

  /// Matchmaking panel: UnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'This battle format is not supported.'**
  String get matchmakingUnsupportedFormat;

  /// Matchmaking panel: UnsupportedFlags.
  ///
  /// In en, this message translates to:
  /// **'The server settings for this format are not supported.'**
  String get matchmakingUnsupportedFlags;

  /// Matchmaking panel: SearchDisabled.
  ///
  /// In en, this message translates to:
  /// **'The server has disabled search for this format.'**
  String get matchmakingSearchDisabled;

  /// Matchmaking panel: TeamRequired.
  ///
  /// In en, this message translates to:
  /// **'This format requires a team; team selection is not supported yet.'**
  String get matchmakingTeamRequired;

  /// Matchmaking panel: ServerNotice.
  ///
  /// In en, this message translates to:
  /// **'The server sent a notice. It does not confirm that the search has ended.'**
  String get matchmakingServerNotice;

  /// Matchmaking panel: SendFailed.
  ///
  /// In en, this message translates to:
  /// **'The command could not be sent reliably. The server outcome is unknown.'**
  String get matchmakingSendFailed;

  /// Matchmaking panel: Timeout.
  ///
  /// In en, this message translates to:
  /// **'No conclusive response arrived in time.'**
  String get matchmakingTimeout;

  /// Matchmaking panel: Conflict.
  ///
  /// In en, this message translates to:
  /// **'Account or battle information changed unexpectedly.'**
  String get matchmakingConflict;

  /// Matchmaking panel: InvalidSnapshot.
  ///
  /// In en, this message translates to:
  /// **'The server sent unreadable search information.'**
  String get matchmakingInvalidSnapshot;
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
