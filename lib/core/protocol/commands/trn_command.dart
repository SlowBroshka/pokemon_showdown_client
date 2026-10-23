import '../client_command.dart';
import 'command_validation.dart';

/// Completes authentication using an assertion obtained by the session layer.
final class TrnCommand extends ClientCommand {
  TrnCommand({required this.username, required this.assertion}) {
    validateCommandField(username, 'username', allowComma: false);
    validateCommandField(assertion, 'assertion');
  }

  final String username;
  final String assertion;

  @override
  String serialize() => '|/trn $username,0,$assertion';
}
