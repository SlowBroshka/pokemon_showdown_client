import 'package:flutter/material.dart';

import '../../core/transport/transport_status.dart';
import '../../l10n/app_localizations.dart';
import 'matchmaking_controller.dart';
import 'matchmaking_message_localization.dart';

/// View only: removing the panel must not cancel a search or release its owner.
class MatchmakingPanel extends StatelessWidget {
  const MatchmakingPanel({
    super.key,
    required this.controller,
    required this.onDisconnect,
  });

  final MatchmakingController controller;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) => StreamBuilder<MatchmakingState>(
    stream: controller.changes,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context)!;
      // Read the live controller, not a potentially queued stream snapshot.
      final state = controller.state;
      final start = controller.captureStart();
      final token = state.attemptToken;
      final recover = state.phase == MatchmakingPhase.outcomeUnknown;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.matchmakingHeading,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.matchmakingFormat,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.matchmakingRatedHint),
          SwitchListTile.adaptive(
            key: const Key('matchmaking.experimental'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.matchmakingExperimental),
            subtitle: Text(l10n.matchmakingExperimentalHint),
            value: controller.experimentalEnabled,
            onChanged: token == null
                ? (value) => controller.experimentalEnabled = value
                : null,
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              localizeMatchmakingPhase(state.phase, l10n),
              key: const Key('matchmaking.status'),
            ),
          ),
          if (state.phase == MatchmakingPhase.unavailable) ...[
            const SizedBox(height: 8),
            Text(
              matchmakingUnavailableReason(controller, l10n),
              key: const Key('matchmaking.reason'),
            ),
          ],
          if (state.notice case final notice?) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                localizeMatchmakingNotice(notice, l10n),
                key: const Key('matchmaking.notice'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('matchmaking.start'),
                onPressed: start == null
                    ? null
                    : () {
                        FocusScope.of(context).unfocus();
                        controller.start(start);
                      },
                child: Text(l10n.matchmakingStart),
              ),
              if (token != null && state.phase != MatchmakingPhase.inBattle)
                OutlinedButton(
                  key: const Key('matchmaking.cancel'),
                  onPressed: controller.canCancel
                      ? () => controller.cancel(token)
                      : null,
                  child: Text(l10n.matchmakingCancel),
                ),
            ],
          ),
          if (token != null && state.phase != MatchmakingPhase.inBattle) ...[
            const SizedBox(height: 8),
            Text(l10n.matchmakingAccountHint),
          ],
          if (recover ||
              (state.phase == MatchmakingPhase.disconnected &&
                  state.notice != null)) ...[
            const SizedBox(height: 12),
            Text(l10n.matchmakingRecoveryHint),
            if (recover)
              OutlinedButton(
                key: const Key('matchmaking.recover'),
                onPressed:
                    controller.session.status == TransportStatus.connected
                    ? onDisconnect
                    : null,
                child: Text(l10n.matchmakingRecover),
              ),
          ],
        ],
      );
    },
  );
}
