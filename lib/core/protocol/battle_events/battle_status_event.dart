import '../server_event.dart';
import '../../battle/requests/pokemon_status.dart';

final class BattleStatusEvent extends ServerEvent {
  const BattleStatusEvent(
    super.record, {
    required this.ident,
    required this.status,
    required this.cured,
  });
  final String ident;
  final PokemonStatus status;
  final bool cured;
}
