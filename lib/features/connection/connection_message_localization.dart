import '../../l10n/app_localizations.dart';
import 'connection_message.dart';

/// Resolve messages at display time, including previously recorded notices.
String localizeConnectionMessage(
  ConnectionMessage message,
  AppLocalizations l10n,
) => switch (message) {
  ConnectionMessage.connectionTimeout => l10n.connectionTimeout,
  ConnectionMessage.serverClosed => l10n.serverClosed,
  ConnectionMessage.unsupportedMessage => l10n.unsupportedMessage,
  ConnectionMessage.sendFailed => l10n.sendFailed,
  ConnectionMessage.connectionFailed => l10n.connectionFailed,
  ConnectionMessage.invalidWssAddress => l10n.invalidWssAddress,
  ConnectionMessage.invalidAddress => l10n.invalidAddress,
  ConnectionMessage.connectionUnavailable => l10n.connectionUnavailable,
  ConnectionMessage.invalidRoomId => l10n.invalidRoomId,
  ConnectionMessage.roomTimeout => l10n.roomTimeout,
  ConnectionMessage.notConnected => l10n.notConnected,
  ConnectionMessage.connecting => l10n.connecting,
  ConnectionMessage.connected => l10n.connected,
  ConnectionMessage.disconnected => l10n.disconnected,
  ConnectionMessage.roomJoined => l10n.roomJoined,
  ConnectionMessage.roomLeft => l10n.roomLeft,
  ConnectionMessage.serverNotice => l10n.serverNotice,
};
