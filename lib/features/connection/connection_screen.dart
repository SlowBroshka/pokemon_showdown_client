import 'package:flutter/material.dart';

import '../../core/transport/transport_status.dart';
import 'connection_controller.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.controller});
  final ConnectionController? controller;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final ConnectionController _controller;
  final _endpoint = TextEditingController(
    text: ConnectionController.defaultEndpoint,
  );
  final _roomId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ConnectionController();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _endpoint.dispose();
    _roomId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pokémon Showdown')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final status = _controller.status;
          final room = _controller.room;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Подключение',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Проверочный экран · одна активная комната\nВход в аккаунт и управление боем появятся позже.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _endpoint,
                    enabled: _controller.canConnect,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Адрес сервера (WSS)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _controller.connect(_endpoint.text),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(switch (status) {
                      TransportStatus.connecting => 'Статус: подключение…',
                      TransportStatus.connected =>
                        'Статус: соединение установлено',
                      _ => 'Статус: отключено',
                    }),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _controller.canConnect
                            ? () => _controller.connect(_endpoint.text)
                            : null,
                        child: const Text('Подключиться'),
                      ),
                      OutlinedButton(
                        onPressed:
                            !_controller.disconnecting &&
                                (status == TransportStatus.connecting ||
                                    status == TransportStatus.connected)
                            ? _controller.disconnect
                            : null,
                        child: Text(
                          status == TransportStatus.connecting
                              ? 'Отменить'
                              : 'Отключиться',
                        ),
                      ),
                    ],
                  ),
                  if (_controller.error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _controller.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                  Text(
                    'Комната',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (room == null) ...[
                    TextField(
                      controller: _roomId,
                      enabled: _controller.canJoin,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'ID комнаты',
                        hintText: 'Например, lobby',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _controller.join(_roomId.text),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _controller.canJoin
                            ? () => _controller.join(_roomId.text)
                            : null,
                        child: const Text('Войти'),
                      ),
                    ),
                    if (_controller.joiningId != null)
                      const Text('Ожидаем подтверждение входа…')
                    else
                      const Text('Активной комнаты нет.'),
                  ] else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.title ?? room.id,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('ID: ${room.id}'),
                            Text(
                              'Тип: ${switch (room.type) {
                                'chat' => 'чат',
                                'battle' => 'бой',
                                _ => 'другой',
                              }}',
                            ),
                            if (room.isStale)
                              const Text(
                                'Данные устарели. Подключитесь и войдите в комнату снова.',
                              ),
                            if (_controller.leaving)
                              const Text('Ожидаем подтверждение выхода…'),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _controller.canLeave
                                  ? _controller.leave
                                  : null,
                              child: const Text('Выйти из комнаты'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                  Text(
                    'Уведомления',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_controller.notices.isEmpty)
                    const Text('Пока нет уведомлений.'),
                  for (final notice in _controller.notices)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(notice),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
