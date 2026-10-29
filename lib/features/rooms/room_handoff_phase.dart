/// Room admission only, not the search queue's lifecycle.
enum RoomHandoffPhase {
  idle,
  reserved,
  awaitingEvidence,
  adopted,
  outcomeUnknown,
}
