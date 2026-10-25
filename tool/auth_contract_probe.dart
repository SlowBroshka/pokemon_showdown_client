// Manual, opt-in compatibility probe. Never runs in CI or during app startup.
// No account credentials, cookies, /trn, room joins or searches are sent.
import 'dart:convert';
import 'dart:io';

const _timeout = Duration(seconds: 12);
const _maxResponseBytes = 64 * 1024;

Future<String> _readBody(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > _maxResponseBytes) {
      throw const FormatException('Response exceeds probe limit');
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

bool? _observedBool(Object? value) => value is bool ? value : null;

Future<void> main() async {
  final observations = <String, Object?>{
    'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'scope': 'Anonymous WSS handshake and empty-credential HTTPS requests only',
  };
  String? challenge;
  WebSocket? socket;
  try {
    socket = await WebSocket.connect('wss://sim3.psim.us/showdown/websocket')
        .timeout(_timeout);
    await for (final frame in socket.timeout(_timeout)) {
      if (frame is! String) continue;
      for (final line in const LineSplitter().convert(frame)) {
        if (line.startsWith('|challstr|')) {
          challenge = line.substring('|challstr|'.length);
          break;
        }
      }
      if (challenge != null) break;
    }
    observations['websocket'] = {
      'challengeReceived': challenge != null && challenge.isNotEmpty,
      'challengeContainsSeparator': challenge?.contains('|') ?? false,
    };
  } catch (_) {
    observations['websocket'] = {
      'error': 'connection_or_challenge_unavailable',
    };
  } finally {
    if (socket != null) {
      await socket.close().timeout(_timeout, onTimeout: () {});
    }
  }

  final probes = <Map<String, Object?>>[];
  for (final path in ['/api/login', '/~~showdown/action.php', '/api/upkeep']) {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.https('play.pokemonshowdown.com', path);
      final request = await client
          .openUrl(path == '/api/upkeep' ? 'GET' : 'POST', uri)
          .timeout(_timeout);
      request.followRedirects = false;
      if (path != '/api/upkeep') {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          Uri(
            queryParameters: {
              if (path.endsWith('action.php')) 'act': 'login',
              'name': '',
              'pass': '',
              'challstr': challenge ?? '0|synthetic-probe-not-a-real-challenge',
            },
          ).query,
        );
      }
      // Anonymous upkeep intentionally has no cookies or challenge query.
      final response = await request.close().timeout(_timeout);
      final body = await _readBody(response).timeout(_timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(body.startsWith(']') ? body.substring(1) : body);
      } on FormatException {
        // Record the category, never an arbitrary response body.
      }
      final object = decoded is Map<String, dynamic> ? decoded : null;
      final currentUser = object?['curuser'];
      probes.add({
        'path': path,
        'method': path == '/api/upkeep' ? 'GET' : 'POST',
        'status': response.statusCode,
        'contentType': response.headers.contentType?.mimeType,
        'redirect': response.isRedirect,
        'prefixedJson': body.startsWith(']') && object != null,
        'jsonKeys': object == null ? null : (object.keys.toList()..sort()),
        'loggedIn': _observedBool(
          currentUser is Map ? currentUser['loggedin'] : null,
        ),
        'sessionLoggedIn': _observedBool(object?['loggedin']),
        'hasError': object?['error'] is String,
        'hasActionError': object?['actionerror'] is String,
        'hasAssertion':
            object?['assertion'] is String &&
            (object!['assertion'] as String).isNotEmpty,
        'setCookieCount': response.cookies.length,
      });
    } catch (_) {
      probes.add({'path': path, 'error': 'request_failed'});
    } finally {
      client.close(force: true);
    }
  }
  observations['http'] = probes;
  observations['limitations'] = [
    'No successful registered-account login or /trn confirmation tested',
    'No authenticated cookies, upkeep, expiration or logout tested',
    'No response bodies, challenges or cookie values recorded',
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(observations));
}
