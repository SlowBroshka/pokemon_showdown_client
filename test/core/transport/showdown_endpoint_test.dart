import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/transport/showdown_endpoint.dart';

void main() {
  test(
    'plaintext is limited to explicitly enabled local development builds',
    () {
      for (final host in ['localhost', '127.0.0.1', '[::1]', '10.0.2.2']) {
        expect(
          isAllowedShowdownEndpoint(
            Uri.parse('ws://$host:8000/showdown/websocket'),
          ),
          localShowdownEnabled,
        );
      }
      for (final value in [
        'ws://example.com',
        'ws://127.0.0.1.example.com',
        'ws://user:pass@localhost',
        'ws://localhost/#fragment',
        'http://localhost',
      ]) {
        expect(isAllowedShowdownEndpoint(Uri.parse(value)), isFalse);
      }
      expect(isAllowedShowdownEndpoint(Uri.parse('wss://example.com')), isTrue);
    },
  );
}
