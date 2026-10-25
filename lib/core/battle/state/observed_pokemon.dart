import 'battle_health.dart';

final class ObservedPokemon {
  const ObservedPokemon({
    required this.ident,
    required this.details,
    required this.health,
    this.teraType,
  });
  final String ident;
  final String details;
  final BattleHealth health;
  final String? teraType;
  String get sideId => ident.substring(0, 2);
  ObservedPokemon withHealth(BattleHealth value) => ObservedPokemon(
    ident: ident,
    details: details,
    health: value,
    teraType: teraType,
  );
  ObservedPokemon withTera(String value) => ObservedPokemon(
    ident: ident,
    details: details,
    health: health,
    teraType: value,
  );
}
