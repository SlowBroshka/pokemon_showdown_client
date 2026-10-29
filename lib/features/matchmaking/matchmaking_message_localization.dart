import '../../core/auth/auth_phase.dart';
import '../../core/matchmaking/formats/format_availability.dart';
import '../../core/transport/transport_status.dart';
import '../../l10n/app_localizations.dart';
import 'matchmaking_controller.dart';

String localizeMatchmakingPhase(
  MatchmakingPhase phase,
  AppLocalizations l10n,
) => switch (phase) {
  MatchmakingPhase.unavailable => l10n.matchmakingUnavailable,
  MatchmakingPhase.idle => l10n.matchmakingIdle,
  MatchmakingPhase.submitting => l10n.matchmakingSubmitting,
  MatchmakingPhase.searching => l10n.matchmakingSearching,
  MatchmakingPhase.cancelling => l10n.matchmakingCancelling,
  MatchmakingPhase.stoppedObserved => l10n.matchmakingStoppedObserved,
  MatchmakingPhase.awaitingBattle => l10n.matchmakingAwaitingBattle,
  MatchmakingPhase.inBattle => l10n.matchmakingInBattle,
  MatchmakingPhase.outcomeUnknown => l10n.matchmakingOutcomeUnknown,
  MatchmakingPhase.disconnected => l10n.matchmakingDisconnected,
};

String localizeMatchmakingNotice(
  MatchmakingNotice notice,
  AppLocalizations l10n,
) => switch (notice) {
  MatchmakingNotice.serverNotice => l10n.matchmakingServerNotice,
  MatchmakingNotice.sendFailed => l10n.matchmakingSendFailed,
  MatchmakingNotice.timeout => l10n.matchmakingTimeout,
  MatchmakingNotice.conflict => l10n.matchmakingConflict,
  MatchmakingNotice.invalidSearchSnapshot => l10n.matchmakingInvalidSnapshot,
};

String localizeFormatAvailability(
  FormatAvailability reason,
  AppLocalizations l10n,
) => switch (reason) {
  FormatAvailability.experimental => l10n.matchmakingNeedData,
  FormatAvailability.staleCatalog => l10n.matchmakingNeedData,
  FormatAvailability.malformedCatalog => l10n.matchmakingMalformedCatalog,
  FormatAvailability.legacyCatalog => l10n.matchmakingLegacyCatalog,
  FormatAvailability.notAdvertised => l10n.matchmakingNotAdvertised,
  FormatAvailability.unsupportedFormat => l10n.matchmakingUnsupportedFormat,
  FormatAvailability.unsupportedFlags => l10n.matchmakingUnsupportedFlags,
  FormatAvailability.searchDisabled => l10n.matchmakingSearchDisabled,
  FormatAvailability.teamRequired => l10n.matchmakingTeamRequired,
  FormatAvailability.experimentalDisabled => l10n.matchmakingNeedExperimental,
};

/// Presentation only; action eligibility always comes from the controller.
String matchmakingUnavailableReason(
  MatchmakingController controller,
  AppLocalizations l10n,
) {
  if (controller.session.status != TransportStatus.connected) {
    return l10n.matchmakingDisconnected;
  }
  if (controller.auth.state.phase != AuthPhase.authenticated) {
    return l10n.matchmakingNeedAccount;
  }
  if (!controller.experimentalEnabled) return l10n.matchmakingNeedExperimental;
  if (!controller.rooms.canJoin) return l10n.matchmakingRoomBusy;
  final snapshot = controller.rooms.searchBaseline;
  if (snapshot?.games?.isNotEmpty == true) return l10n.matchmakingExistingGame;
  if (snapshot?.searching.isNotEmpty == true) {
    return l10n.matchmakingExternalSearch;
  }
  return localizeFormatAvailability(
    controller.catalog.availability(
      MatchmakingController.formatId,
      experimentalEnabled: controller.experimentalEnabled,
    ),
    l10n,
  );
}
