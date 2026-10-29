import '../client_command.dart';
import 'command_validation.dart';

/// Builds a search command; catalog, session and identity checks belong to the
/// future search controller. Construction and serialization never send it.
final class SearchBattleCommand extends ClientCommand {
  SearchBattleCommand({required this.formatId}) {
    validateSearchFormatId(formatId);
  }

  final String formatId;

  @override
  String serialize() => '|/search $formatId';
}
