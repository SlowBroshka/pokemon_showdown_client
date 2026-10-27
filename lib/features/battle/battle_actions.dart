import 'package:flutter/material.dart';

import '../../core/battle/decisions/battle_decision_controller.dart';
import '../../l10n/app_localizations.dart';

/// The parent keys this widget by request revision; no draft survives refresh.
class BattleActions extends StatefulWidget {
  const BattleActions({super.key, required this.controller});
  final BattleDecisionController controller;
  @override
  State<BattleActions> createState() => _BattleActionsState();
}

class _BattleActionsState extends State<BattleActions> {
  bool _tera = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final controller = widget.controller;
    final request = controller.state.request;
    if (request == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (request.active case final active?) ...[
          Text(l.battleMoves, style: Theme.of(context).textTheme.titleMedium),
          if (request.canTerastallize)
            CheckboxListTile(
              key: const Key('battle.tera'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.battleTera),
              subtitle: Text(active.canTerastallize!),
              value: _tera,
              onChanged: controller.canChoose
                  ? (value) => setState(() => _tera = value!)
                  : null,
            ),
          for (final move in active.moves)
            _button(
              key: Key('battle.move.${move.slot}'),
              choice: BattleChoice.move(move.slot, terastallize: _tera),
              label:
                  '${l.battleMove(move.slot, move.name)}\n${l.battlePp(move.pp ?? 0, move.maxPp?.toString() ?? '?')}',
            ),
        ],
        if (request.side case final side?)
          for (final pokemon in side.pokemon)
            _button(
              key: Key('battle.switch.${pokemon.slot}'),
              choice: BattleChoice.switchTo(pokemon.slot),
              label: l.battleSwitch(pokemon.ident),
            ),
      ],
    );
  }

  Widget _button({
    required Key key,
    required BattleChoice choice,
    required String label,
  }) {
    // Capture at render time, not on tap: an obsolete callback must not select
    // the same slot of a different request while a rebuild is still pending.
    final captured = widget.controller.capture(choice);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton(
        key: key,
        onPressed: captured == null
            ? null
            : () => widget.controller.submit(captured),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
