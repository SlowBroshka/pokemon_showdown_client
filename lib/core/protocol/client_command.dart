/// A validated outgoing command. Serialization does not send it to a server.
abstract class ClientCommand {
  const ClientCommand();

  /// Returns one complete WebSocket text message, without a final newline.
  /// The result may contain an assertion and must not be logged.
  String serialize();
}
