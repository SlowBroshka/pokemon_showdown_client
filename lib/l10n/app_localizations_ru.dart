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
      'Одна активная комната · вход в аккаунт · прототип боя';

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

  @override
  String get authHeading => 'Аккаунт';

  @override
  String get authDescription =>
      'Используйте существующий аккаунт. Пароль не сохраняется.';

  @override
  String get authUsername => 'Имя пользователя';

  @override
  String get authPassword => 'Пароль';

  @override
  String get authShowPassword => 'Показать пароль';

  @override
  String get authHidePassword => 'Скрыть пароль';

  @override
  String get authSignIn => 'Войти в аккаунт';

  @override
  String get authCancelSignIn => 'Отменить вход';

  @override
  String get authSignOut => 'Выйти и отключиться';

  @override
  String get authDisconnected => 'Подключитесь к серверу для входа.';

  @override
  String get authUnavailable => 'Вход недоступен для этого сервера.';

  @override
  String get authWaitingChallenge => 'Ожидаем данные для входа от сервера…';

  @override
  String get authReady => 'Можно войти в аккаунт.';

  @override
  String get authAuthenticating => 'Проверяем учётные данные…';

  @override
  String get authAwaitingConfirmation =>
      'Ожидаем подтверждение входа игровым сервером…';

  @override
  String authSignedIn(String username) {
    return 'Вход выполнен: $username';
  }

  @override
  String get authDisconnecting => 'Отключаемся…';

  @override
  String get authDisposed => 'Сеанс завершён.';

  @override
  String get authInvalidInput =>
      'Проверьте имя и пароль. Имя — до 18 символов, с латинскими буквами или цифрами.';

  @override
  String get authNetwork =>
      'Не удалось связаться со службой входа. Повторите попытку.';

  @override
  String get authTimeout => 'Время ожидания входа истекло. Повторите попытку.';

  @override
  String get authCancelled => 'Вход отменён.';

  @override
  String get authUnexpectedRedirect =>
      'Служба входа вернула неожиданное перенаправление. Вход остановлен.';

  @override
  String get authRateLimited =>
      'Слишком много попыток входа. Подождите перед повтором.';

  @override
  String get authServiceUnavailable => 'Служба входа временно недоступна.';

  @override
  String get authHttpFailure => 'Служба входа не смогла обработать запрос.';

  @override
  String get authInvalidResponse =>
      'Служба входа вернула неподдерживаемый ответ.';

  @override
  String get authResponseTooLarge =>
      'Ответ службы входа превысил допустимый размер.';

  @override
  String get authLoginRejected =>
      'Вход отклонён. Проверьте данные аккаунта и повторите попытку.';

  @override
  String get authInvalidAssertion =>
      'Служба входа вернула некорректные данные подтверждения.';

  @override
  String get authUnsupportedServer =>
      'Вход в аккаунт пока поддерживается только на основном сервере Pokémon Showdown.';

  @override
  String get authChallengeTimeout =>
      'Сервер не прислал данные для входа. Подключитесь снова.';

  @override
  String get authConfirmationTimeout =>
      'Игровой сервер не подтвердил вход. Подключитесь снова.';

  @override
  String get authIdentityRejected =>
      'Игровой сервер не подтвердил аккаунт. Подключитесь снова.';

  @override
  String get authConnectionLost =>
      'Соединение потеряно. Подключитесь и войдите снова.';

  @override
  String get authSendFailed => 'Не удалось завершить вход. Подключитесь снова.';

  @override
  String get authInvalidServerEvent =>
      'Сервер прислал некорректные данные входа. Подключитесь снова.';

  @override
  String get battleHeading => 'Бой';

  @override
  String get battleScope =>
      'Прототип: Gen 9 singles. Неподдерживаемые механики блокируют выбор.';

  @override
  String battleTurn(int turn) {
    return 'Ход $turn';
  }

  @override
  String get battlePublicField => 'Активные Pokémon · публичные данные';

  @override
  String get battleUnknown => 'Не раскрыто';

  @override
  String battlePublicHp(int hp, String maximum) {
    return 'Сообщённые HP: $hp/$maximum';
  }

  @override
  String battlePrivateHp(int hp, String maximum) {
    return 'HP: $hp/$maximum';
  }

  @override
  String get battleFainted => 'Без сознания';

  @override
  String battleStatus(String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'brn': 'ожог',
      'par': 'паралич',
      'psn': 'отравление',
      'tox': 'сильное отравление',
      'slp': 'сон',
      'frz': 'заморозка',
      'other': 'нет',
    });
    return 'Статус: $_temp0';
  }

  @override
  String battleTeraType(String type) {
    return 'Тератип: $type';
  }

  @override
  String get battleTeam => 'Ваша команда · последний приватный снимок';

  @override
  String get battleActive => 'На поле';

  @override
  String get battleMoves => 'Выберите атаку';

  @override
  String battlePp(int current, String maximum) {
    return 'PP: $current/$maximum';
  }

  @override
  String battleMove(int slot, String name) {
    return '$slot. $name';
  }

  @override
  String battleSwitch(String name) {
    return 'Заменить на $name';
  }

  @override
  String get battleTera => 'Терастализация вместе с атакой';

  @override
  String get battleReady => 'Выберите атаку или доступную замену.';

  @override
  String get battleForced => 'Выберите замену.';

  @override
  String get battleWaiting => 'Ожидание следующего решения…';

  @override
  String get battleSubmitted => 'Выбор отправлен. Ожидание сервера…';

  @override
  String get battleUncertain =>
      'Результат отправки неизвестен. Ожидаем новый запрос; автоматического повтора нет.';

  @override
  String get battleUnavailable =>
      'Выбор недоступен. Ожидаем обновлённые варианты от сервера.';

  @override
  String get battleRejected => 'Сервер отклонил выбор. Можно выбрать заново.';

  @override
  String get battleUnsupported =>
      'Это состояние боя не поддерживается. Выбор отключён.';

  @override
  String get battleMalformed =>
      'Не удалось прочитать варианты решения от сервера. Ожидаем обновление.';

  @override
  String get battleStopped => 'Выбор в этой комнате отключён.';

  @override
  String get battleClosed => 'Комната закрыта. Результат не сообщён.';

  @override
  String battleWinner(String name) {
    return 'Победитель: $name';
  }

  @override
  String get battleTie => 'Бой завершился ничьей.';

  @override
  String get battleLog => 'Последние действия';

  @override
  String battleLogMove(int turn, String actor, String action) {
    return 'Ход $turn: $actor использует $action.';
  }

  @override
  String battleLogCant(int turn, String actor, String action) {
    return 'Ход $turn: $actor не смог действовать ($action).';
  }

  @override
  String get battleLogEmpty => 'Действий пока нет.';
}
