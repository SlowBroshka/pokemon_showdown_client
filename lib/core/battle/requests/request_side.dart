import 'request_pokemon.dart';

final class RequestSide {
  RequestSide({
    required this.id,
    required this.name,
    required List<RequestPokemon> pokemon,
  }) : pokemon = List.unmodifiable(pokemon);
  final String id;
  final String? name;
  final List<RequestPokemon> pokemon;
}
