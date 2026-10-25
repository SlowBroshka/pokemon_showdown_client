import 'dart:async';

import 'package:http/http.dart' as http;

final class FakeAuthHttpClient extends http.BaseClient {
  FakeAuthHttpClient(this.respond);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];
  bool closed = false;
  bool failClose = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return await respond(request);
  }

  @override
  void close() {
    closed = true;
    if (failClose) throw StateError('private-cleanup-secret');
  }
}
