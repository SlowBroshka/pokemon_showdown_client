import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_transport.dart';

import 'package:pokemon_showdown_client/core/auth/auth_controller.dart';
import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_controller.dart';
import 'package:pokemon_showdown_client/core/protocol/client_command.dart';
import 'package:pokemon_showdown_client/core/protocol/server_event_decoder.dart';
import 'package:pokemon_showdown_client/core/session/showdown_session.dart';
import 'package:pokemon_showdown_client/features/connection/connection_controller.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';

/// Only loaded by opt-in tests. No password, login HTTP or public endpoint.
final class LocalMatchmakingClient {
  LocalMatchmakingClient(this.name) {
    session = ShowdownSession(
      transport: ShowdownTransport(
        channelFactory: (uri) => RecordingChannel(uri, sent),
      ),
    );
    auth = AuthController(session: session);
    catalog = FormatCatalogController(session: session);
    connection = ConnectionController(session: session);
    search = MatchmakingController(
      session: session,
      auth: auth,
      catalog: catalog,
      rooms: connection.rooms,
      localTestUserId: name.toLowerCase(),
      experimentalEnabled: true,
      responseTimeout: const Duration(seconds: 3),
    );
    subscription = session.updates.listen((u) {
      if (u.event is UpdateSearchEvent) {
        searchUpdates++;
        final snapshot = (u.event as UpdateSearchEvent).result.snapshot;
        if (snapshot != null) {
          events.add(
            snapshot.searching.isNotEmpty
                ? 'queued'
                : (snapshot.games?.isNotEmpty ?? false)
                ? 'games'
                : 'empty',
          );
        }
        if (named) baselineAfterIdentity = true;
      }
      if (u.event case final UpdateUserEvent event) {
        named = event.named && event.user.trim() == name;
      }
      if (u.event is RoomInitEvent && u.roomId?.startsWith('battle-') == true) {
        events.add('init');
      }
      if (u.event is BattleRequestEvent) {
        requests++;
        events.add('request');
      }
    });
  }
  final String name;
  final sent = <String>[];
  final events = <String>[];
  late final ShowdownSession session;
  late final AuthController auth;
  late final FormatCatalogController catalog;
  late final ConnectionController connection;
  late final MatchmakingController search;
  late final StreamSubscription<SessionUpdate> subscription;
  bool _initialized = false;
  bool named = false;
  bool baselineAfterIdentity = false;
  int searchUpdates = 0;
  int requests = 0;

  Future<void> connect({String host = '127.0.0.1'}) async {
    if (!const ['127.0.0.1', '10.0.2.2'].contains(host)) {
      throw ArgumentError('Loopback only');
    }
    named = false;
    baselineAfterIdentity = false;
    await session.connect(Uri.parse('ws://$host:8001/showdown/websocket'));
    await until(() => catalog.fresh);
    session.send(
      _LocalCommand('|/trn $name,0,'),
      connectionEpoch: session.connectionEpoch,
    );
    await until(() => named, label: 'local name');
    // A fresh rename does not emit updatesearch. Rejoining an existing identity
    // uses the real server mergeConnection path and supplies its current queue.
    if (!_initialized) {
      _initialized = true;
      await session.disconnect();
      return connect(host: host);
    }
    await until(
      () => named && baselineAfterIdentity && catalog.fresh,
      label: 'confirmed local identity',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sent.clear();
    events.clear();
  }

  void start() {
    final action = search.captureStart();
    if (action == null || !search.start(action)) {
      throw StateError('Search unavailable: ${search.state.phase}');
    }
  }

  Future<void> close() async {
    await search.dispose();
    connection.dispose();
    await connection.closed;
    await catalog.dispose();
    await auth.dispose();
    await subscription.cancel();
    await session.dispose();
  }
}

Future<void> until(
  bool Function() predicate, {
  String label = 'condition',
}) async {
  for (var i = 0; i < 1000; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('Timed out waiting for $label');
}

final class _LocalCommand extends ClientCommand {
  _LocalCommand(this.text);
  final String text;
  @override
  String serialize() => text;
}

final class RecordingChannel implements WebSocketChannel {
  RecordingChannel(Uri uri, List<String> sent)
    : inner = IOWebSocketChannel.connect(uri) {
    sink = RecordingSink(inner.sink, sent);
  }
  final WebSocketChannel inner;
  @override
  late final WebSocketSink sink;
  @override
  Stream<dynamic> get stream => inner.stream;
  @override
  Future<void> get ready => inner.ready;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class RecordingSink implements WebSocketSink {
  RecordingSink(this.inner, this.sent);
  final WebSocketSink inner;
  final List<String> sent;
  @override
  void add(dynamic data) {
    sent.add(data as String);
    inner.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) => inner.close(code, reason);
  @override
  Future<void> get done => inner.done;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
