import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/auth/auth_controller.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_controller.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';
import 'package:pokemon_showdown_client/features/rooms/room_owner.dart';

import '../../core/transport/support/fake_socket_channel.dart';

void main() {
  const enabled =
      bool.fromEnvironment('SHOWDOWN_LOCAL') &&
      bool.fromEnvironment('SHOWDOWN_MATCHMAKING_TEST') &&
      !bool.fromEnvironment('dart.vm.product');
  late FakeSocketChannel socket;
  late ShowdownSession session;
  late AuthController auth;
  late FormatCatalogController catalog;
  late RoomOwner rooms;
  MatchmakingController? search;
  setUp(() {
    socket = FakeSocketChannel();
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    auth = AuthController(session: session);
    catalog = FormatCatalogController(session: session);
    rooms = RoomOwner(session);
  });
  tearDown(() async {
    await search?.dispose();
    search = null;
    rooms.dispose();
    await rooms.closed;
    await catalog.dispose();
    await auth.dispose();
    await session.dispose();
    await socket.incoming.close();
  });
  MatchmakingController create() => MatchmakingController(
    session: session,
    auth: auth,
    catalog: catalog,
    rooms: rooms,
    localTestUserId: 'localtester',
    experimentalEnabled: true,
  );
  Future<void> receive(String value) async {
    socket.incoming.add(value);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('test identity cannot be enabled in ordinary builds', () {
    if (enabled) {
      search = create();
    } else {
      expect(create, throwsArgumentError);
    }
  });
  for (final address in [
    'ws://127.0.0.1:8001/showdown/websocket',
    'wss://sim3.psim.us/showdown/websocket',
  ]) {
    test('test identity scope: $address', () async {
      search = create();
      final pending = session.connect(Uri.parse(address));
      socket.handshake.complete();
      await pending;
      await receive(
        '|formats|,1|Singles|[Gen 9] Random Battle,4f\n|updateuser| LocalTester|1|1|{}\n|updatesearch|{"searching":[],"games":null}',
      );
      expect(search!.canStart, address.startsWith('ws:'));
      if (search!.canStart) {
        search!.start(search!.captureStart()!);
        final token = search!.state.attemptToken!;
        await receive('|updateuser| Other|1|1|{}');
        expect(search!.canStart, isFalse);
        expect(search!.cancel(token), isFalse);
      } else {
        expect(socket.sink.sent, isEmpty);
      }
    }, skip: !enabled);
  }
}
