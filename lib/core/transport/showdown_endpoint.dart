/// Opt-in development build only. Never accepts remote plaintext endpoints.
const localShowdownEnabled =
    bool.fromEnvironment('SHOWDOWN_LOCAL') &&
    !bool.fromEnvironment('dart.vm.product');

bool isAllowedShowdownEndpoint(Uri endpoint) =>
    endpoint.host.isNotEmpty &&
    endpoint.userInfo.isEmpty &&
    !endpoint.hasFragment &&
    (endpoint.scheme == 'wss' ||
        (localShowdownEnabled &&
            endpoint.scheme == 'ws' &&
            const [
              'localhost',
              '127.0.0.1',
              '::1',
              '10.0.2.2',
            ].contains(endpoint.host)));
