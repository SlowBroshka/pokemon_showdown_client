enum BattleRequestKind {
  noRequest,
  wait,
  move,
  switchRequest,
  malformedRequest,
  unsupportedRequest;

  String get wireName => this == switchRequest ? 'switch' : name;
}
