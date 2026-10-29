import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/client_commands.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../transport/support/fake_socket_channel.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSocketChannel socket;
  late List<FakeSocketChannel> sockets;
  late ShowdownSession session;
  setUp(() {
    socket = FakeSocketChannel();
    sockets = [socket];
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
  });
  tearDown(() async {
    await session.dispose();
    for (final s in sockets) {
      await s.incoming.close();
    }
  });
  Future<void> connect() async {
    final pending = session.connect(Uri.parse('wss://example.test'));
    socket.handshake.complete();
    await pending;
    await flush();
  }

  test(
    'routes valid/malformed updates once in order without replying',
    () async {
      final events = <SessionUpdate>[];
      final sub = session.globalEvents.listen(events.add);
      await connect();
      socket.incoming.add(
        '|updatesearch|{"searching":["gen9randombattle"],"games":null}\n|updatesearch|{\n|updatesearch|{"searching":[],"games":{}}',
      );
      await flush();
      expect(events, hasLength(3));
      final results = events
          .map((e) => (e.event as UpdateSearchEvent).result)
          .toList();
      expect(results.map((r) => r.isValid), [true, false, true]);
      expect(results.first.snapshot!.searching, ['gen9randombattle']);
      expect(results.last.snapshot!.games, isEmpty);
      expect(events.map((e) => e.sequence).toSet(), hasLength(1));
      expect(events.every((e) => e.connectionEpoch == 1), isTrue);
      socket.incoming.add(
        '>battle-other\n|updatesearch|{"searching":[],"games":null}',
      );
      await flush();
      expect(events, hasLength(3));
      expect(socket.sink.sent, isEmpty);
      await sub.cancel();
    },
  );

  test(
    'commands use shared transport and cannot cross connection epochs',
    () async {
      final commands = <ClientCommand>[
        const PrepareRandomTeamCommand(),
        SearchBattleCommand(formatId: 'gen9randombattle'),
        CancelSearchCommand(formatId: 'gen9randombattle'),
      ];
      await connect();
      final epoch = session.connectionEpoch;
      for (final c in commands) {
        session.send(c, connectionEpoch: epoch);
      }
      expect(socket.sink.sent, [
        '|/utm null',
        '|/search gen9randombattle',
        '|/cancelsearch gen9randombattle',
      ]);
      await session.disconnect();
      for (final c in commands) {
        expect(() => session.send(c, connectionEpoch: epoch), throwsStateError);
      }
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect();
      for (final c in commands) {
        expect(() => session.send(c, connectionEpoch: epoch), throwsStateError);
      }
      expect(socket.sink.sent, isEmpty);
    },
  );
}
