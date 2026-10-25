import '../../core/auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';

String localizeAuthPhase(AuthState state, AppLocalizations l10n) =>
    switch (state.phase) {
      AuthPhase.disconnected => l10n.authDisconnected,
      AuthPhase.unavailable => l10n.authUnavailable,
      AuthPhase.waitingChallenge => l10n.authWaitingChallenge,
      AuthPhase.ready => l10n.authReady,
      AuthPhase.authenticating => l10n.authAuthenticating,
      AuthPhase.awaitingConfirmation => l10n.authAwaitingConfirmation,
      AuthPhase.authenticated => l10n.authSignedIn(state.username!),
      AuthPhase.disconnecting => l10n.authDisconnecting,
      AuthPhase.disposed => l10n.authDisposed,
    };

String localizeAuthFailure(AuthFailure failure, AppLocalizations l10n) =>
    switch (failure) {
      AuthFailure.invalidInput => l10n.authInvalidInput,
      AuthFailure.network => l10n.authNetwork,
      AuthFailure.timeout => l10n.authTimeout,
      AuthFailure.cancelled => l10n.authCancelled,
      AuthFailure.unexpectedRedirect => l10n.authUnexpectedRedirect,
      AuthFailure.rateLimited => l10n.authRateLimited,
      AuthFailure.serviceUnavailable => l10n.authServiceUnavailable,
      AuthFailure.httpFailure => l10n.authHttpFailure,
      AuthFailure.invalidResponse => l10n.authInvalidResponse,
      AuthFailure.responseTooLarge => l10n.authResponseTooLarge,
      AuthFailure.loginRejected => l10n.authLoginRejected,
      AuthFailure.invalidAssertion => l10n.authInvalidAssertion,
      AuthFailure.unsupportedServer => l10n.authUnsupportedServer,
      AuthFailure.challengeTimeout => l10n.authChallengeTimeout,
      AuthFailure.confirmationTimeout => l10n.authConfirmationTimeout,
      AuthFailure.identityRejected => l10n.authIdentityRejected,
      AuthFailure.connectionLost => l10n.authConnectionLost,
      AuthFailure.sendFailed => l10n.authSendFailed,
      AuthFailure.invalidServerEvent => l10n.authInvalidServerEvent,
    };
