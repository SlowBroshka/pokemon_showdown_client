// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get connectionTimeout => 'Время подключения истекло.';

  @override
  String get serverClosed => 'Сервер закрыл соединение.';

  @override
  String get unsupportedMessage => 'Сервер прислал неподдерживаемое сообщение.';

  @override
  String get sendFailed => 'Не удалось отправить команду.';

  @override
  String get connectionFailed =>
      'Ошибка соединения. Попробуйте подключиться снова.';

  @override
  String get invalidWssAddress =>
      'Введите WSS-адрес без логина, пароля и фрагмента.';

  @override
  String get invalidAddress => 'Некорректный адрес сервера.';

  @override
  String get connectionUnavailable => 'Подключение сейчас недоступно.';

  @override
  String get invalidRoomId =>
      'ID комнаты: строчные латинские буквы, цифры и дефисы.';

  @override
  String get roomTimeout =>
      'Сервер не подтвердил действие. Соединение закрыто; подключитесь снова.';

  @override
  String get notConnected => 'Нет соединения с сервером.';

  @override
  String get connecting => 'Подключение…';

  @override
  String get connected => 'Соединение установлено.';

  @override
  String get disconnected => 'Соединение закрыто.';

  @override
  String get roomJoined => 'Вход в комнату подтверждён.';

  @override
  String get roomLeft => 'Выход из комнаты подтверждён.';

  @override
  String get serverNotice =>
      'Сервер отклонил действие или прислал уведомление. Возможно, требуется вход в аккаунт.';

  @override
  String get appTitle => 'Pokémon Showdown';

  @override
  String get connectionHeading => 'Подключение';

  @override
  String get connectionDescription =>
      'Проверочный экран · одна активная комната\nВход в аккаунт и управление боем появятся позже.';

  @override
  String get serverAddress => 'Адрес сервера (WSS)';

  @override
  String get statusConnecting => 'Статус: подключение…';

  @override
  String get statusConnected => 'Статус: соединение установлено';

  @override
  String get statusDisconnected => 'Статус: отключено';

  @override
  String get connect => 'Подключиться';

  @override
  String get cancel => 'Отменить';

  @override
  String get disconnect => 'Отключиться';

  @override
  String get roomHeading => 'Комната';

  @override
  String get roomIdLabel => 'ID комнаты';

  @override
  String get roomIdHint => 'Например, lobby';

  @override
  String get join => 'Войти';

  @override
  String get awaitingJoin => 'Ожидаем подтверждение входа…';

  @override
  String get noActiveRoom => 'Активной комнаты нет.';

  @override
  String get staleRoom =>
      'Данные устарели. Подключитесь и войдите в комнату снова.';

  @override
  String get awaitingLeave => 'Ожидаем подтверждение выхода…';

  @override
  String get leaveRoom => 'Выйти из комнаты';

  @override
  String get noticesHeading => 'Уведомления';

  @override
  String get noNotices => 'Пока нет уведомлений.';

  @override
  String roomIdValue(String roomId) {
    return 'ID: $roomId';
  }

  @override
  String roomType(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'chat': 'чат',
      'battle': 'бой',
      'other': 'другой',
    });
    return 'Тип: $_temp0';
  }
}
