import '../server_event.dart';

final class ChallengeEvent extends ServerEvent {
  const ChallengeEvent(super.record, {required this.challenge});

  final String challenge;
}
