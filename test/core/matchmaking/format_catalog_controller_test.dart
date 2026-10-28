import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_availability.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_controller.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_kind.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import '../transport/support/fake_socket_channel.dart';

const wire = '|formats|,1|Singles|[Gen 9] Random Battle,4f';
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakeSocketChannel socket;
  late List<FakeSocketChannel> sockets;
  late ShowdownSession session;
  late FormatCatalogController catalog;
  setUp(() {
    socket = FakeSocketChannel();
    sockets = [socket];
    session = ShowdownSession(
      transport: ShowdownTransport(channelFactory: (_) => socket),
    );
    catalog = FormatCatalogController(session: session);
  });
  tearDown(() async {
    await catalog.dispose();
    await session.dispose();
    for (final s in sockets) {
      await s.incoming.close();
    }
  });
  Future<void> connect() async {
    final future = session.connect(Uri.parse('wss://example.test'));
    socket.handshake.complete();
    await future;
    await flush();
  }

  Future<void> receive(String data) async {
    socket.incoming.add(data);
    await flush();
  }

  FormatAvailability availability() =>
      catalog.availability('gen9randombattle', experimentalEnabled: true);

  test(
    'receives early catalog; availability requires completed connection',
    () async {
      final future = session.connect(Uri.parse('wss://example.test'));
      await receive(wire);
      expect(catalog.catalog, isNotNull);
      expect(catalog.fresh, isFalse);
      socket.handshake.complete();
      await future;
      await flush();
      expect(availability(), FormatAvailability.experimental);
      expect(socket.sink.sent, isEmpty);
    },
  );

  test(
    'replaces valid catalog with malformed, empty and removed target',
    () async {
      await connect();
      await receive(wire);
      final previous = catalog.catalog;
      expect(availability(), FormatAvailability.experimental);
      await receive('|formats|Bad,zz');
      expect(catalog.catalog!.kind, FormatCatalogKind.malformed);
      expect(availability(), FormatAvailability.malformedCatalog);
      expect(previous!.formats, hasLength(1));
      await receive(wire);
      await receive('|formats');
      expect(availability(), FormatAvailability.notAdvertised);
      await receive('|formats|[Gen 9] OU,e');
      expect(catalog.catalog!.formats.keys, ['gen9ou']);
      expect(availability(), FormatAvailability.notAdvertised);
    },
  );

  test(
    'room-scoped updates and unrelated records do not replace catalog',
    () async {
      await connect();
      await receive(wire);
      final previous = catalog.catalog;
      await receive('>other\n|formats|Bad,zz');
      expect(catalog.catalog, same(previous));
      expect(availability(), FormatAvailability.experimental);
      await receive('|updatesearch|{"searching":[],"games":null}');
      expect(catalog.catalog, same(previous));
    },
  );

  test(
    'never exposes first valid record as actionable within same frame',
    () async {
      await connect();
      final seen = <FormatAvailability>[];
      final sub = session.updates.listen((u) {
        if (u.event is FormatsEvent) seen.add(availability());
      });
      await receive('$wire\n|formats|Bad,zz');
      expect(seen, hasLength(2));
      expect(seen, everyElement(FormatAvailability.staleCatalog));
      expect(availability(), FormatAvailability.malformedCatalog);
      await sub.cancel();
    },
  );

  test(
    'disconnect revokes synchronously and reconnect needs a new catalog',
    () async {
      await connect();
      await receive(wire);
      final closing = session.disconnect();
      expect(catalog.fresh, isFalse);
      await closing;
      socket = FakeSocketChannel();
      sockets.add(socket);
      await connect();
      expect(catalog.catalog, isNull);
      expect(availability(), FormatAvailability.staleCatalog);
      sockets.first.incoming.add(wire);
      await flush();
      expect(catalog.catalog, isNull);
      await receive(wire);
      expect(availability(), FormatAvailability.experimental);
    },
  );

  test('queued old epoch cannot replace new catalog', () async {
    await connect();
    // Invalidate the epoch before downstream catalog delivery.
    final oldCatalog = catalog;
    await oldCatalog.dispose();
    final invalidator = session.updates.listen((u) {
      if (u.event is FormatsEvent && u.connectionEpoch == 1) {
        unawaited(session.disconnect());
      }
    });
    catalog = FormatCatalogController(session: session);
    await receive(wire);
    expect(catalog.catalog, isNull);
    await invalidator.cancel();
    socket = FakeSocketChannel();
    sockets.add(socket);
    await connect();
    await receive('|formats|[Gen 9] OU,e');
    expect(catalog.catalog!.formats.keys, ['gen9ou']);
  });

  test(
    'source progress revokes availability before catalog delivery',
    () async {
      await catalog.dispose();
      final seen = <FormatAvailability>[];
      final early = session.updates.listen((u) {
        if (u.event is FormatsEvent) seen.add(availability());
      });
      catalog = FormatCatalogController(session: session);
      await connect();
      await receive(wire);
      expect(availability(), FormatAvailability.experimental);
      seen.clear();
      await receive('|formats|Bad,zz');
      expect(seen, [FormatAvailability.staleCatalog]);
      expect(availability(), FormatAvailability.malformedCatalog);
      await early.cancel();
    },
  );

  test('dispose closes notifications without closing shared session', () async {
    await connect();
    await receive(wire);
    final done = Completer<void>();
    catalog.changes.listen((_) {}, onDone: done.complete);
    final disposal = catalog.dispose();
    expect(catalog.fresh, isFalse);
    expect(catalog.dispose(), same(disposal));
    await disposal;
    await done.future;
    expect(session.status, TransportStatus.connected);
    await receive(wire);
    expect(catalog.catalog, isNull);
    expect(socket.sink.sent, isEmpty);
  });
}
