final class RequestMove {
  const RequestMove({
    required this.slot,
    required this.name,
    required this.id,
    required this.target,
    required this.pp,
    required this.maxPp,
    required this.disabled,
  });
  final int slot;
  final String name;
  final String id;
  final String target;
  final int? pp;
  final int? maxPp;
  final bool disabled;
  bool get available => !disabled && (id == 'struggle' || (pp ?? 0) > 0);
}
