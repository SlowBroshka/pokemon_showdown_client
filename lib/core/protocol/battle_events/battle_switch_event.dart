import '../server_event.dart';
import '../../battle/state/observed_pokemon.dart';

final class BattleSwitchEvent extends ServerEvent {
  const BattleSwitchEvent(
    super.record, {
    required this.pokemon,
    required this.dragged,
    this.source,
  });
  final ObservedPokemon pokemon;
  final bool dragged;
  final String? source;
}
