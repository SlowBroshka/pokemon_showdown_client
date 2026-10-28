import 'package:flutter/material.dart';

import '../../core/battle/decisions/battle_decision_controller.dart';
import '../../core/battle/requests/battle_request_kind.dart';
import '../../core/battle/state/battle_phase.dart';
import '../../l10n/app_localizations.dart';
import 'battle_actions.dart';

/// Renders typed snapshots only. The application owns the controller/session.
class BattlePanel extends StatelessWidget {
  const BattlePanel({super.key, required this.controller});
  final BattleDecisionController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: controller.changes,
    builder: (context, _) {
      final l = AppLocalizations.of(context)!;
      final s = controller.state;
      final result = s.result;
      final request = s.request;
      final message = s.stale
          ? l.staleRoom
          : result != null
          ? (result.isTie ? l.battleTie : l.battleWinner(result.winner!))
          : s.phase == BattlePhase.closed
          ? l.battleClosed
          : s.unsupported ||
                request?.kind == BattleRequestKind.unsupportedRequest
          ? l.battleUnsupported
          : request?.kind == BattleRequestKind.malformedRequest
          ? l.battleMalformed
          : switch (controller.phase) {
              BattleDecisionPhase.submitted => l.battleSubmitted,
              BattleDecisionPhase.uncertain => l.battleUncertain,
              BattleDecisionPhase.awaitingRequest => l.battleUnavailable,
              BattleDecisionPhase.inactive => l.battleStopped,
              BattleDecisionPhase.ready =>
                controller.canChoose
                    ? (controller.choiceRejected
                          ? l.battleRejected
                          : request?.kind == BattleRequestKind.switchRequest
                          ? l.battleForced
                          : l.battleReady)
                    : l.battleWaiting,
            };
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.battleHeading,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(s.title ?? s.roomId),
              Text(l.battleScope),
              const SizedBox(height: 12),
              Text(
                l.battleTurn(s.turn),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Semantics(
                liveRegion: true,
                child: Text(message, key: const Key('battle.message')),
              ),
              if (s.stale && result != null)
                Text(
                  result.isTie ? l.battleTie : l.battleWinner(result.winner!),
                ),
              const Divider(),
              Text(
                l.battlePublicField,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final side in ['p1', 'p2']) ...[
                const SizedBox(height: 8),
                Text(s.players[side]?.name ?? side),
                if (s.active[side] case final pokemon?) ...[
                  Text(pokemon.ident),
                  Text(pokemon.details),
                  Text(
                    l.battlePublicHp(
                      pokemon.health.hp,
                      pokemon.health.maxHp?.toString() ?? '?',
                    ),
                  ),
                  if (pokemon.health.fainted) Text(l.battleFainted),
                  Text(l.battleStatus(pokemon.health.status?.name ?? 'none')),
                  if (pokemon.teraType case final type?)
                    Text(l.battleTeraType(type)),
                ] else
                  Text(l.battleUnknown),
              ],
              const Divider(),
              BattleActions(
                key: ValueKey(s.requestRevision),
                controller: controller,
              ),
              if (s.privateSide case final side?) ...[
                const Divider(),
                Text(
                  l.battleTeam,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final pokemon in side.pokemon)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.battleMove(pokemon.slot, pokemon.ident)),
                        Text(pokemon.details),
                        Text(
                          l.battlePrivateHp(
                            pokemon.condition.hp,
                            pokemon.condition.maxHp?.toString() ?? '?',
                          ),
                        ),
                        if (pokemon.active) Text(l.battleActive),
                        if (pokemon.condition.fainted) Text(l.battleFainted),
                        Text(
                          l.battleStatus(
                            pokemon.condition.status?.name ?? 'none',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const Divider(),
              Text(l.battleLog, style: Theme.of(context).textTheme.titleMedium),
              if (s.log.isEmpty) Text(l.battleLogEmpty),
              for (final entry in s.log.reversed.take(20))
                Text(
                  entry.cannotAct
                      ? l.battleLogCant(entry.turn, entry.actor, entry.action)
                      : l.battleLogMove(entry.turn, entry.actor, entry.action),
                ),
            ],
          ),
        ),
      );
    },
  );
}
