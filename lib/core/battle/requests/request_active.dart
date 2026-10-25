import 'request_move.dart';

final class RequestActive {
  RequestActive({
    required List<RequestMove> moves,
    required this.trapped,
    required this.maybeTrapped,
    required this.maybeDisabled,
    required this.maybeLocked,
    this.canTerastallize,
  }) : moves = List.unmodifiable(moves);
  final List<RequestMove> moves;
  final bool trapped;
  final bool maybeTrapped;
  final bool maybeDisabled;
  final bool maybeLocked;
  final String? canTerastallize;
}
