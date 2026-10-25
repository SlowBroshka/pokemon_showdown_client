/// Conservative ASCII identity policy for the first supported login flow.
/// The server remains authoritative; no Unicode transliteration is attempted.
String? authUserId(String name) {
  if (name.isEmpty ||
      name.length > 18 ||
      name.trim() != name ||
      name.codeUnits.any((value) => value < 32 || value > 126) ||
      name.contains(RegExp(r'[|,;]'))) {
    return null;
  }
  final id = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return id.isEmpty ? null : id;
}
