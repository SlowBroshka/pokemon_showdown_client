import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/protocol/client_commands.dart';
import '../../core/protocol/server_event_decoder.dart';
import '../../core/rooms/room_router.dart';
import '../../core/transport/showdown_transport.dart';

/// Owns the transport and router. One selected room and one operation at a time.
final class ConnectionController extends ChangeNotifier {
  ConnectionController({
    ShowdownTransport? transport,
    this.roomTimeout = const Duration(seconds: 10),
  }) : _transport = transport ?? ShowdownTransport() {
    if (roomTimeout <= Duration.zero) {
      throw ArgumentError('Timeout must be positive');
    }
    _router = RoomRouter(_transport);
    _subscriptions.addAll([
      _transport.statuses.listen(_onStatus),
      _transport.failures.listen(
        (failure) => _report(switch (failure.failure) {
          TransportFailure.timeout => 'Время подключения истекло.',
          TransportFailure.closed => 'Сервер закрыл соединение.',
          TransportFailure.unsupportedMessage =>
            'Сервер прислал неподдерживаемое сообщение.',
          TransportFailure.send => 'Не удалось отправить команду.',
          _ => 'Ошибка соединения. Попробуйте подключиться снова.',
        }),
      ),
      _router.roomEvents.listen(_onRoom),
      _router.globalEvents.listen(_onGlobal),
    ]);
  }

  static const defaultEndpoint = 'wss://sim3.psim.us/showdown/websocket';
  final ShowdownTransport _transport;
  final Duration roomTimeout;
  late final RoomRouter _router;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _notices = <String>[];
  RoomInfo? _room;
  String? _joiningId;
  bool _leaving = false;
  bool _disconnecting = false;
  bool _disposed = false;
  Timer? _timer;
  String? _error;
  Future<void>? _cleanup;

  TransportStatus get status => _transport.status;
  RoomInfo? get room => _room;
  String? get joiningId => _joiningId;
  bool get leaving => _leaving;
  bool get disconnecting => _disconnecting;
  String? get error => _error;
  List<String> get notices => List.unmodifiable(_notices);
  bool get canConnect =>
      !_disposed && !_disconnecting && status == TransportStatus.disconnected;
  bool get canJoin =>
      !_disposed &&
      !_disconnecting &&
      status == TransportStatus.connected &&
      _room == null &&
      _joiningId == null &&
      !_leaving;
  bool get canLeave =>
      !_disposed &&
      !_disconnecting &&
      status == TransportStatus.connected &&
      _room != null &&
      !_room!.isStale &&
      !_leaving;

  Future<void> connect(String address) async {
    if (!canConnect) return;
    _error = null;
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      _report('Введите WSS-адрес без логина, пароля и фрагмента.');
      return;
    }
    _room = null;
    try {
      final pending = _transport.connect(uri);
      _changed();
      await pending;
    } on TransportException {
      // The failures stream reports network failures; cancellation is intentional.
    } on ArgumentError {
      _report('Некорректный адрес сервера.');
    } on StateError {
      _report('Подключение сейчас недоступно.');
    }
    _changed();
  }

  Future<void> disconnect() async {
    if (_disposed || _disconnecting) return;
    _disconnecting = true;
    _clearOperation();
    _stale();
    final pending = _transport.disconnect();
    _changed();
    await pending;
    _disconnecting = false;
    _changed();
  }

  void join(String id) {
    if (!canJoin) return;
    final JoinRoomCommand command;
    try {
      command = JoinRoomCommand(roomId: id.trim());
    } on ArgumentError {
      _report('ID комнаты: строчные латинские буквы, цифры и дефисы.');
      return;
    }
    _error = null;
    _joiningId = command.roomId;
    _awaitRoom();
    _send(command);
    _changed();
  }

  void leave() {
    if (!canLeave) return;
    _error = null;
    _leaving = true;
    _awaitRoom();
    _send(LeaveRoomCommand(roomId: _room!.id));
    _changed();
  }

  void _awaitRoom() {
    _timer?.cancel();
    _timer = Timer(roomTimeout, () {
      _report(
        'Сервер не подтвердил действие. Соединение закрыто; подключитесь снова.',
      );
      // A late init must not create a second room after a timed-out join.
      unawaited(disconnect());
    });
  }

  void _send(ClientCommand command) {
    try {
      _transport.send(command);
    } on TransportException {
      _clearOperation();
    } on StateError {
      _clearOperation();
      _report('Нет соединения с сервером.');
    }
  }

  void _onStatus(TransportStatus value) {
    if (_disposed) return;
    if (value == TransportStatus.disconnected ||
        value == TransportStatus.disposed) {
      _clearOperation();
      _stale();
    }
    _notice(switch (value) {
      TransportStatus.connecting => 'Подключение…',
      TransportStatus.connected => 'Соединение установлено.',
      _ => 'Соединение закрыто.',
    });
  }

  void _onRoom(RoomEvent routed) {
    if (_disposed || status != TransportStatus.connected || _disconnecting) {
      return;
    }
    final event = routed.event;
    final id = routed.roomId;
    if (event is RoomInitEvent) {
      if (_joiningId == id || _room?.id == id) {
        _room = RoomInfo(id: id, type: event.roomType);
        if (_joiningId == id) _clearOperation();
        _notice('Вход в комнату подтверждён.');
      } else {
        // No unsolicited room becomes active. Keep the lower-level router general.
        try {
          _send(LeaveRoomCommand(roomId: id));
        } on ArgumentError {
          unawaited(disconnect());
        }
      }
    } else if (event is RoomTitleEvent && _room?.id == id) {
      _room = RoomInfo(id: id, type: _room!.type, title: event.title);
      _changed();
    } else if (event is RoomDeinitEvent &&
        (_room?.id == id || _joiningId == id)) {
      _room = null;
      _clearOperation();
      _notice('Выход из комнаты подтверждён.');
    } else if (id == _joiningId || id == _room?.id) {
      _onGlobal(event);
    }
  }

  void _onGlobal(ServerEvent event) {
    if (_disposed || _disconnecting || status != TransportStatus.connected) {
      return;
    }
    if (event is ServerErrorEvent ||
        event is PopupEvent ||
        event is NameTakenEvent ||
        (event is UnknownServerEvent && event.eventType == 'noinit')) {
      _report(
        'Сервер отклонил действие или прислал уведомление. Возможно, требуется вход в аккаунт.',
      );
      if (_joiningId != null || _leaving) unawaited(disconnect());
    }
  }

  void _stale() {
    final previous = _room;
    if (previous != null) {
      _room = RoomInfo(
        id: previous.id,
        type: previous.type,
        title: previous.title,
        isStale: true,
      );
    }
  }

  void _clearOperation() {
    _timer?.cancel();
    _timer = null;
    _joiningId = null;
    _leaving = false;
  }

  void _report(String message) {
    if (_disposed) return;
    _error = message;
    _notice(message);
  }

  void _notice(String message) {
    if (_disposed) return;
    _notices.insert(0, message);
    if (_notices.length > 50) _notices.removeLast();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Completion of resource cleanup after dispose(), useful for the app owner/tests.
  Future<void> get closed => _cleanup ?? Future.value();
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearOperation();
    _cleanup = _closeResources();
    super.dispose();
  }

  Future<void> _closeResources() async {
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _router.dispose();
    await _transport.dispose();
  }
}
