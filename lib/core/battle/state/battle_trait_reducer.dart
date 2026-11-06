import '../../protocol/battle_events/battle_trait_event.dart';
import 'battle_state.dart';
import 'effect_observation.dart';
import 'pokemon_traits.dart';

bool knownTraitActor(BattleState state, String ident) =>
    state.active[ident.substring(0, 2)]?.ident == ident;

BattleState? reduceTraits(BattleState state, BattleTraitEvent event) {
  if (!knownTraitActor(state, event.actor)) return null;
  if (event.other != null && !knownTraitActor(state, event.other!)) return null;
  final actor = state.active[event.actor.substring(0, 2)]!;
  var traits = actor.traits;
  var roster = state.roster;
  final source = event.source;
  final from = source == null ? null : '${source.kind.name}: ${source.name}';
  String? owner = event.actor;
  switch (event.operation) {
    case TraitOperation.item:
      traits = traits.holding(event.name!);
      if ({
        'move: Covet',
        'move: Thief',
        'move: Bestow',
        'ability: Magician',
        'ability: Pickpocket',
      }.contains(from)) {
        if (event.other == event.actor) return null;
        final donor = state.active[event.other!.substring(0, 2)]!;
        if (donor.traits.itemKnowledge == ItemKnowledge.held &&
            donor.traits.item != event.name) {
          return null;
        }
        roster = roster.updateActive([
          donor.withTraits(
            donor.traits.ending(event.name!, ItemEndReason.transferred),
          ),
        ]);
      }
      // [of] is the donor for stealing, but the ability holder for Frisk.
      if (from == 'ability: Frisk') {
        owner = event.other;
      } else if (source?.kind == EffectSourceKind.move) {
        owner = null;
      }
    case TraitOperation.endItem:
      if (traits.itemKnowledge == ItemKnowledge.held &&
          traits.item != event.name) {
        return null;
      }
      traits = traits.ending(event.name!, event.itemEndReason!);
      owner = source == null ? event.actor : null;
    // Donor/source roles vary; preserve relation without guessing.
    case TraitOperation.ability:
      traits = traits.withAbility(event.name!, previous: event.previous);
      // Trace's [of] identifies the copied Pokemon, not the owner of Trace.
      owner =
          source == null ||
              (source.kind == EffectSourceKind.ability &&
                  source.name == 'Trace')
          ? event.actor
          : event.other;
    case TraitOperation.suppressAbility:
      traits = traits.suppress();
    case TraitOperation.skillSwap:
      if (event.other == event.actor) return null;
      final other = state.active[event.other!.substring(0, 2)]!;
      traits = traits.withAbility(event.name!, previous: event.otherAbility);
      roster = roster.updateActive([
        other.withTraits(
          other.traits.withAbility(event.otherAbility!, previous: event.name),
        ),
      ]);
      owner = event.actor;
    case TraitOperation.activate:
      if (source?.kind == EffectSourceKind.move &&
          source?.name == 'Substitute' &&
          !actor.effects.volatiles.containsKey('substitute')) {
        return null;
      }
    // An activation is evidence, not a fresh current ability/item assignment.
    case TraitOperation.block:
      owner = event.other ?? event.actor;
    case TraitOperation.notice:
      owner =
          source?.kind == EffectSourceKind.item ||
              source?.kind == EffectSourceKind.ability
          ? event.other ?? event.actor
          : source?.kind == EffectSourceKind.move
          ? event.other
          : null;
  }
  final updated = state.copyWith(
    roster: roster.updateActive([actor.withTraits(traits)]),
  );
  final effect =
      source ??
      PublicEffectSource(
        kind:
            event.operation == TraitOperation.item ||
                event.operation == TraitOperation.endItem
            ? EffectSourceKind.item
            : EffectSourceKind.ability,
        name: event.name ?? traits.ability ?? 'unknown',
      );
  return recordEffect(
    updated,
    event.record.eventType!,
    effect,
    event.actor,
    owner,
  );
}

BattleState recordEffect(
  BattleState state,
  String type,
  PublicEffectSource source,
  String? target,
  String? owner,
) {
  int? appearance(String? ident) =>
      ident != null &&
          ident.length >= 2 &&
          state.active[ident.substring(0, 2)]?.ident == ident
      ? state.roster.activeIds[ident.substring(0, 2)]
      : null;
  final entries = [
    ...state.effectObservations,
    EffectObservation(
      eventType: type,
      turn: state.turn,
      effect: source,
      targetIdent: target,
      targetAppearanceId: appearance(target),
      sourceAppearanceId: appearance(owner),
    ),
  ];
  return state.copyWith(
    effectObservations: entries.length <= maxEffectObservations
        ? entries
        : entries.sublist(entries.length - maxEffectObservations),
  );
}
