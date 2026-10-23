import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

final class FakeSocketSink implements WebSocketSink {
  final sent = <Object?>[];
  final completed = Completer<void>();
  bool closed = false;
  bool failSend = false;
  bool hangOnClose = false;

  @override
  void add(dynamic data) {
    if (failSend) throw StateError('secret payload');
    sent.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    closed = true;
    if (!hangOnClose && !completed.isCompleted) completed.complete();
    return completed.future;
  }

  @override
  Future<void> get done => completed.future;

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnimplementedError();

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }
}
