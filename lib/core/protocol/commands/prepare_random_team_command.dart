import '../client_command.dart';

/// Selects server-provided teams. The literal "null" is protocol text, not JSON.
final class PrepareRandomTeamCommand extends ClientCommand {
  const PrepareRandomTeamCommand();

  @override
  String serialize() => '|/utm null';
}
