final _unsafeCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029|]');
final _roomCharacters = RegExp(r'[^a-z0-9-]');

/// Checks framing safety, not server-side account or authorization rules.
void validateCommandField(
  String value,
  String field, {
  bool allowComma = true,
}) {
  if (value.isEmpty ||
      value.trim() != value ||
      _unsafeCharacters.hasMatch(value) ||
      (!allowComma && value.contains(','))) {
    // Do not include the rejected value: it may be an authentication assertion.
    throw ArgumentError('Invalid $field');
  }
}

void validateCommandRoomId(String roomId) {
  validateCommandField(roomId, 'roomId');
  if (_roomCharacters.hasMatch(roomId)) {
    throw ArgumentError('Invalid roomId');
  }
}
