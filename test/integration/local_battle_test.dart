import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/battle/decisions/battle_decision_controller.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/battle/requests/battle_request_kind.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';

void main() {
  for (final forced in [false, true]) {
    test(
      'real local engine: refusal, switch, tera, result and disconnect (forced=$forced)',
      () async {
        final session = ShowdownSession();
        final owner = ConnectionController(session: session);
        final types = <String>{};
        final events = session.updates.listen((u) {
          if (u.event case final UnknownServerEvent event) {
            types.add(event.eventType);
          }
        });
        try {
          await owner.connect('ws://127.0.0.1:8000/showdown/websocket');
          expect(session.status, TransportStatus.connected);
          owner.join(forced ? 'battle-local-force' : 'battle-local');
          Future<void> until(bool Function() predicate) async {
            for (var i = 0; i < 500; i++) {
              if (predicate()) return;
              if (owner.battle?.state.unsupported == true) {
                fail('Unsupported live state. Unknown event types: $types');
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            fail(
              'Timed out: phase=${owner.battle?.phase}, request=${owner.battle?.state.request?.kind}, reason=${owner.battle?.state.request?.reason}',
            );
          }

          await until(() => owner.battle?.canChoose == true);
          final battle = owner.battle!;
          Future<void> choose(BattleChoice choice) async {
            final revision = battle.state.requestRevision;
            final capture = battle.capture(choice);
            expect(capture, isNotNull);
            expect(battle.submit(capture!), isTrue);
            await until(
              () =>
                  battle.choiceRejected ||
                  battle.state.requestRevision > revision ||
                  battle.state.terminal,
            );
            await until(() => battle.canChoose || battle.state.terminal);
          }

          await choose(const BattleChoice.move(1));
          expect(battle.choiceRejected, isTrue);
          if (forced) {
            await choose(const BattleChoice.move(1));
            expect(battle.state.request!.kind, BattleRequestKind.switchRequest);
            expect(battle.state.request!.moveSlots, isEmpty);
          }
          await choose(const BattleChoice.switchTo(2));
          await choose(const BattleChoice.move(1, terastallize: true));
          for (var turn = 0; turn < 150 && !battle.state.terminal; turn++) {
            await choose(const BattleChoice.move(1));
          }
          expect(battle.state.result?.winner, 'LocalPlayer');
          await owner.disconnect();
          await until(() => battle.state.stale);
          expect(battle.canChoose, isFalse);
        } finally {
          owner.dispose();
          await owner.closed;
          await events.cancel();
          await session.dispose();
        }
      },
      skip: !const bool.fromEnvironment('SHOWDOWN_LIVE'),
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
