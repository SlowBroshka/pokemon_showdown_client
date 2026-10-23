import '../client_command.dart';
import 'command_validation.dart';

/// Joins the specified server room.
final class JoinRoomCommand extends ClientCommand {
  JoinRoomCommand({required this.roomId}) {
    validateCommandRoomId(roomId);
  }

  final String roomId;

  @override
  String serialize() => '|/join $roomId';
}
