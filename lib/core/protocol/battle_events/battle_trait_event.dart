import '../server_event.dart';
import '../../battle/state/effect_observation.dart';
import '../../battle/state/pokemon_traits.dart';

enum TraitOperation {
  item,
  endItem,
  ability,
  suppressAbility,
  activate,
  block,
  skillSwap,
  notice,
}

final class BattleTraitEvent extends ServerEvent {
  const BattleTraitEvent(
    super.record, {
    required this.operation,
    required this.actor,
    this.name,
    this.previous,
    this.other,
    this.otherAbility,
    this.source,
    this.itemEndReason,
  });
  final TraitOperation operation;
  final String actor;
  final String? name;
  final String? previous;
  final String? other;
  final String? otherAbility;
  final PublicEffectSource? source;
  final ItemEndReason? itemEndReason;
}

final class BattleAttributedEvent extends ServerEvent {
  BattleAttributedEvent(this.inner, this.source) : super(inner.record);
  final ServerEvent inner;
  final PublicEffectSource source;
}
