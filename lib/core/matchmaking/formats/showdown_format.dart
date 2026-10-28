/// Server-advertised metadata, not a claim of client battle compatibility.
final class ShowdownFormat {
  const ShowdownFormat({
    required this.id,
    required this.name,
    required this.section,
    required this.column,
    required this.flags,
  });

  final String id;
  final String name;
  final String section;
  final int column;

  /// Null denotes legacy syntax. BigInt preserves unknown high bits exactly.
  final BigInt? flags;
  bool _has(int mask) =>
      flags != null && (flags! & BigInt.from(mask)) != BigInt.zero;
  bool get preset => _has(1);
  bool get searchShow => _has(2);
  bool get challengeShow => _has(4);
  bool get tournamentShow => _has(8);
  bool get level50 => _has(16);
  bool get partner => _has(32);
  bool get bestOfDefault => _has(64);
  bool get teraPreviewDefault => _has(128);
  bool get itemClauseDefault => _has(256);
  bool get unsupported =>
      flags == null || partner || (flags! >> 9) != BigInt.zero;
}
