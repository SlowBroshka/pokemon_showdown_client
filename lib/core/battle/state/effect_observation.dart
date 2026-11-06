enum EffectSourceKind { item, ability, move, condition }

final class PublicEffectSource {
  const PublicEffectSource({
    required this.kind,
    required this.name,
    this.ofIdent,
  });
  final EffectSourceKind kind;
  final String name;

  /// Literal public relation. Its role depends on the event, not always owner.
  final String? ofIdent;
}

const maxEffectObservations = 200;

/// No raw record, private request or guessed persistent ownership.
final class EffectObservation {
  const EffectObservation({
    required this.eventType,
    required this.turn,
    required this.effect,
    this.targetIdent,
    this.targetAppearanceId,
    this.sourceAppearanceId,
  });
  final String eventType;
  final int turn;
  final PublicEffectSource effect;
  final String? targetIdent;
  final int? targetAppearanceId;

  /// Only set when the reviewed event semantics identify the effect owner.
  final int? sourceAppearanceId;
}
