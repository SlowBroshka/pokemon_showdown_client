import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/client_command.dart';
import 'transport_exception.dart';
import 'transport_failure.dart';
import 'transport_status.dart';
import 'transport_update.dart';

export 'transport_exception.dart';
export 'transport_failure.dart';
export 'transport_status.dart';
export 'transport_update.dart';

/// Native Android/Linux transport. No parsing, auth, queue or automatic retry.
/// Subscribe before connecting: broadcast streams do not replay old events.
final class ShowdownTransport {
  ShowdownTransport({
    this.connectTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 2),
    this.channelFactory,
  }) {
    if (connectTimeout <= Duration.zero || closeTimeout <= Duration.zero) {
      throw ArgumentError('Timeouts must be positive');
    }
  }

  final Duration connectTimeout;
  final Duration closeTimeout;

  /// Optional test adapter. Production uses a native WSS channel.
  final WebSocketChannel Function(Uri)? channelFactory;
  final _messages = StreamController<String>.broadcast();
  final _updates = StreamController<TransportUpdate>.broadcast();
  final _statuses = StreamController<TransportStatus>.broadcast();
  final _failures = StreamController<TransportException>.broadcast();
  WebSocketChannel? _channel;
  HttpClient? _httpClient;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _pending;
  Timer? _timer;
  Future<void>? _disposal;
  TransportStatus _status = TransportStatus.disconnected;
  int _updateSequence = 0;

  TransportStatus get status => _status;
  int get latestUpdateSequence => _updateSequence;
  Stream<String> get messages => _messages.stream;

  /// Preserves relative order of messages and status changes for state reducers.
  Stream<TransportUpdate> get updates => _updates.stream;
  Stream<TransportStatus> get statuses => _statuses.stream;

  /// Typed notifications, not Stream errors. connect() also reports its failure.
  Stream<TransportException> get failures => _failures.stream;

  Future<void> connect(Uri endpoint) {
    if (_status != TransportStatus.disconnected) {
      throw StateError('Transport must be disconnected before connecting');
    }
    if (endpoint.scheme != 'wss' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment) {
      throw ArgumentError(
        'Expected a WSS endpoint without credentials or fragment',
      );
    }
    final pending = Completer<void>();
    _pending = pending;
    _setStatus(TransportStatus.connecting);
    try {
      final factory = channelFactory;
      final WebSocketChannel channel;
      if (factory != null) {
        channel = factory(endpoint);
      } else {
        final client = HttpClient()..connectionTimeout = connectTimeout;
        _httpClient = client;
        channel = IOWebSocketChannel.connect(
          endpoint,
          customClient: client,
          pingInterval: const Duration(seconds: 30),
        );
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        (dynamic message) {
          if (!identical(_channel, channel)) return;
          if (message is String) {
            _updates.add(
              TransportUpdate.message(message, sequence: ++_updateSequence),
            );
            _messages.add(message);
          } else {
            _fail(TransportFailure.unsupportedMessage);
          }
        },
        onError: (Object error) {
          if (identical(_channel, channel)) _fail(TransportFailure.connection);
        },
        onDone: () {
          if (identical(_channel, channel)) _fail(TransportFailure.closed);
        },
      );
      _timer = Timer(connectTimeout, () => _fail(TransportFailure.timeout));
      channel.ready.then(
        (_) {
          if (!identical(_channel, channel)) return;
          _timer?.cancel();
          _timer = null;
          _pending = null;
          _setStatus(TransportStatus.connected);
          pending.complete();
        },
        onError: (Object error) {
          if (identical(_channel, channel)) _fail(TransportFailure.connection);
        },
      );
    } catch (_) {
      _fail(TransportFailure.connection);
    }
    return pending.future;
  }

  /// Acceptance by the local sink is not acknowledgement by the server.
  void send(ClientCommand command) {
    if (_status != TransportStatus.connected) {
      throw StateError('Transport is not connected');
    }
    final text = command.serialize();
    // Also guard custom ClientCommand implementations against batched commands.
    if (text.contains('\n') || text.contains('\r')) {
      throw ArgumentError('Command must be a single line');
    }
    try {
      _channel!.sink.add(text);
    } catch (_) {
      _fail(TransportFailure.send);
      throw const TransportException(TransportFailure.send);
    }
  }

  Future<void> disconnect() {
    if (_status == TransportStatus.disposed) return Future.value();
    return _stop(TransportFailure.cancelled);
  }

  /// Idempotent terminal close. A new instance is required after disposal.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    final cleanup = _stop(TransportFailure.cancelled);
    _setStatus(TransportStatus.disposed);
    await cleanup;
    await Future.wait([
      _messages.close(),
      _updates.close(),
      _statuses.close(),
      _failures.close(),
    ]);
  }

  void _fail(TransportFailure failure) {
    if (_status == TransportStatus.disconnected ||
        _status == TransportStatus.disposed) {
      return;
    }
    _failures.add(TransportException(failure));
    unawaited(_stop(failure));
  }

  Future<void> _stop(TransportFailure failure) {
    final channel = _channel;
    final subscription = _subscription;
    final client = _httpClient;
    _channel = null;
    _subscription = null;
    _httpClient = null;
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    pending?.completeError(TransportException(failure));
    _setStatus(TransportStatus.disconnected);
    // Cancel pending HTTP handshakes as well as closing established sockets.
    client?.close(force: true);
    return Future.wait([
      if (subscription != null) _quietly(subscription.cancel),
      if (channel != null) _quietly(() => channel.sink.close(1000)),
    ]);
  }

  Future<void> _quietly(Future<dynamic> Function() action) async {
    try {
      await action().timeout(closeTimeout);
    } catch (_) {
      // Closing is best effort and bounded; never expose socket error contents.
    }
  }

  void _setStatus(TransportStatus value) {
    if (_status == value) return;
    _status = value;
    _updates.add(TransportUpdate.status(value, sequence: ++_updateSequence));
    _statuses.add(value);
  }
}
