import '../client_command.dart';
import 'command_validation.dart';

/// Targeted cancellation only: cannot serialize the account-wide cancel form.
final class CancelSearchCommand extends ClientCommand {
  CancelSearchCommand({required this.formatId}) {
    validateSearchFormatId(formatId);
  }

  final String formatId;

  @override
  String serialize() => '|/cancelsearch $formatId';
}
