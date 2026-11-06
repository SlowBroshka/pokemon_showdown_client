enum ItemKnowledge { unknown, held, absent }

enum ItemEndReason { consumed, removed, transferred, ended }

/// Public evidence scoped to an appearance; not the private request inventory.
final class PokemonTraits {
  const PokemonTraits({
    this.itemKnowledge = ItemKnowledge.unknown,
    this.item,
    this.lastEndedItem,
    this.itemEndReason,
    this.ability,
    this.previousAbility,
    this.suppressed = false,
  });
  final ItemKnowledge itemKnowledge;
  final String? item;
  final String? lastEndedItem;
  final ItemEndReason? itemEndReason;
  final String? ability;
  final String? previousAbility;

  /// Explicit -endability observation, not a simulation of global suppression.
  final bool suppressed;
  PokemonTraits holding(String name) => PokemonTraits(
    itemKnowledge: ItemKnowledge.held,
    item: name,
    lastEndedItem: lastEndedItem,
    itemEndReason: itemEndReason,
    ability: ability,
    previousAbility: previousAbility,
    suppressed: suppressed,
  );
  PokemonTraits ending(String name, ItemEndReason reason) => PokemonTraits(
    itemKnowledge: ItemKnowledge.absent,
    lastEndedItem: name,
    itemEndReason: reason,
    ability: ability,
    previousAbility: previousAbility,
    suppressed: suppressed,
  );
  PokemonTraits withAbility(String name, {String? previous}) => PokemonTraits(
    itemKnowledge: itemKnowledge,
    item: item,
    lastEndedItem: lastEndedItem,
    itemEndReason: itemEndReason,
    ability: name,
    previousAbility: previous ?? previousAbility,
    suppressed: suppressed,
  );
  PokemonTraits suppress() => PokemonTraits(
    itemKnowledge: itemKnowledge,
    item: item,
    lastEndedItem: lastEndedItem,
    itemEndReason: itemEndReason,
    ability: ability,
    previousAbility: previousAbility,
    suppressed: true,
  );
}
