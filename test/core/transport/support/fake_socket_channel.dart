import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'fake_socket_sink.dart';

final class FakeSocketChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final handshake = Completer<void>();
  @override
  final FakeSocketSink sink = FakeSocketSink();
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  Future<void> get ready => handshake.future;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;

  // StreamChannel transformation methods are not used by the transport.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
