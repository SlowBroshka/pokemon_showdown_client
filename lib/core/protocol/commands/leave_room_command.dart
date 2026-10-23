import '../client_command.dart';
import 'command_validation.dart';

/// Leaves the room; this is not a battle forfeit command.
final class LeaveRoomCommand extends ClientCommand {
  LeaveRoomCommand({required this.roomId}) {
    validateCommandRoomId(roomId);
  }

  final String roomId;

  @override
  String serialize() => '$roomId|/leave';
}
