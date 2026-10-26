import '../../battle/decisions/battle_choice.dart';
import '../client_command.dart';
import 'command_validation.dart';

/// A single explicit decision. No queueing, undo, or automatic retry.
final class ChooseCommand extends ClientCommand {
  ChooseCommand({required this.roomId, required this.choice, this.rqid}) {
    validateCommandRoomId(roomId);
    if (choice.slot < 1 || choice.slot > (choice.isMove ? 4 : 6)) {
      throw ArgumentError('Invalid choice slot');
    }
    if (rqid != null && rqid! < 0) throw ArgumentError('Invalid request id');
  }

  final String roomId;
  final BattleChoice choice;
  final int? rqid;

  @override
  String serialize() =>
      '$roomId|/choose ${choice.isMove ? 'move' : 'switch'} ${choice.slot}'
      '${choice.terastallize ? ' terastallize' : ''}'
      '${rqid == null ? '' : '|$rqid'}';
}
