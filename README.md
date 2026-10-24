# pokemon_showdown_client

A new Flutter project.

## Разбор сообщений Showdown

Официальная спецификация: [PROTOCOL.md → Server-to-client messages](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#server-to-client-messages).
Раздел описывает заголовок комнаты `>ROOMID`, разделение на строки и оболочку
`|TYPE|DATA`. Ссылка закреплена на версии из архитектурного исследования.
Примеры текста с символом `|` приведены в разделе [Room messages](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#room-messages).

Спецификация предписывает игнорировать пустые строки; наш низкоуровневый парсер
сохраняет их как `empty`, чтобы следующий слой мог их пропустить. Неизменяемость
записей и обработка некорректного заголовка — контракт этого модуля.

`lib/core/protocol/server_message.dart` — модуль на чистом Dart без дополнительных
зависимостей. `parseServerMessage(String message)` принимает одно полное текстовое
сообщение WebSocket и возвращает неизменяемый список `ServerRecord` в порядке
получения. Каждая запись содержит `roomId`, `rawLine`, `kind`, `eventType` и `data`.

- `>ROOMID` меняет контекст внутри сообщения и не создаёт запись. Каждый вызов
  начинается с глобального контекста (`roomId == null`). Пустой заголовок `>`
  создаёт запись `malformed` с глобальным контекстом и сбрасывает текущую комнату.
- `|TYPE|DATA` создаёт запись `event`. Хвост `data` сохраняется целиком, включая
  `|`, пробелы, JSON и HTML. Для `|TYPE` данные равны пустой строке. Пустое имя
  события также сохраняется: `|` и `||text` остаются событиями.
- Обычные и пустые строки имеют виды `text` и `empty`; их `eventType` и `data`
  равны `null`. Исходный текст доступен в `rawLine`.
- `rawLine` не содержит завершающий LF или CRLF. Одиночный CR сохраняется.
  Пустое сообщение возвращает пустой список, завершающий перенос не добавляет
  лишнюю запись; внутренние пустые строки сохраняются.

Парсер не проверяет семантику событий и идентификаторов комнат, не разбирает JSON,
не отображает HTML и не подключается к серверу. Неизвестное событие сохраняется
как `event`; решение о его поддержке принимает следующий слой. Записи могут
содержать приватные данные сервера и не предназначены для безусловного логирования.

Проверка контракта на синтетических сообщениях:

```bash
flutter test test/core/protocol/server_message_test.dart
```

## Типизированные события сервера

`lib/core/protocol/server_event_decoder.dart` экспортирует
`decodeServerRecord(ServerRecord)` и модели событий. Декодер не зависит от Flutter
и не меняет состояние приложения. Каждый класс находится в отдельном файле.

```dart
for (final record in parseServerMessage(message)) {
  final event = decodeServerRecord(record);
  if (event == null) continue; // Пустая строка.
  // Передать событие следующему слою.
}
```

| Событие | Модель и поля |
|---|---|
| `challstr` | `ChallengeEvent.challenge`: полный challenge с символами `\|` |
| `updateuser` | `UpdateUserEvent`: `user`, `named`, `avatar`, `settingsJson` |
| `init` | `RoomInitEvent.roomType` |
| `title` | `RoomTitleEvent.title` |
| `deinit` | `RoomDeinitEvent` |
| `error` | `ServerErrorEvent.message` |
| `popup` | `PopupEvent.message`: исходный текст, включая `\|\|` |
| `nametaken` | `NameTakenEvent`: `username`, `message` |
| Обычный текст / `\|\|text` | `PlainTextEvent.text` |

У всех моделей есть исходная неизменяемая `record` и доступ к `roomId`.
Неизвестные типы (включая боевые события и HTML) становятся `UnknownServerEvent`,
повреждённые записи — `MalformedServerEvent` с причиной без входных данных.
Такие результаты не прерывают обработку следующих записей. Исходная `record`
может содержать секреты; её нельзя безусловно писать в журнал.

Контракт декодера: пустые строки дают `null`; текстовые хвосты сохраняются без
обрезки пробелов. В `updateuser` обязательны непустые USER и AVATAR и флаг `0`/`1`.
USER сохраняется вместе с рангом/статусом; `named` не доказывает регистрацию.
SETTINGS при наличии проверяется как JSON-объект и хранится исходной строкой,
чтобы модель оставалась неизменяемой; отсутствие поля допускается для старого
формата и даёт `null`, пустое или повреждённое поле считается ошибкой.
Challenge, тип комнаты, заголовок и оба поля `nametaken` должны быть непустыми;
`deinit` не принимает данные. Пустые `error`/`popup` сохраняются.
Новые типы комнат сохраняются строкой; допустимость комнаты и её контекста
проверит будущий маршрутизатор, глобальный контекст здесь остаётся `null`.

Источники для проверки полей: официальный
[PROTOCOL.md → Global messages](https://github.com/smogon/pokemon-showdown/blob/master/PROTOCOL.md#global-messages),
[Room initialization](https://github.com/smogon/pokemon-showdown/blob/master/PROTOCOL.md#room-initialization)
и [Room messages](https://github.com/smogon/pokemon-showdown/blob/master/PROTOCOL.md#room-messages).
Обработка `deinit` дополнительно сверена с методом `receive` в
[официальном клиенте](https://github.com/smogon/pokemon-showdown-client/blob/master/play.pokemonshowdown.com/src/client-main.ts).
Эти ссылки на `master` проверены 23 октября 2026 года и могут меняться.
Правила отклонения некорректных полей и поддержки старого `updateuser` — решения
нашего клиента, а не дополнительные требования спецификации.

Тесты декодера: `flutter test test/core/protocol/server_event_decoder_test.dart`.

## Исходящие команды

`lib/core/protocol/client_commands.dart` экспортирует общий интерфейс
`ClientCommand` и три неизменяемые модели (каждая в отдельном файле):

| Модель | Результат `serialize()` |
|---|---|
| `TrnCommand(username: 'Alice', assertion: 'token')` | `\|/trn Alice,0,token` |
| `JoinRoomCommand(roomId: 'lobby')` | `\|/join lobby` |
| `LeaveRoomCommand(roomId: 'lobby')` | `lobby\|/leave` |

Сериализация возвращает одно полное текстовое сообщение без завершающего
переноса строки. Модуль не открывает соединение и ничего не отправляет.
`/trn` использует готовый assertion, а не пароль; получение assertion относится
к будущему модулю авторизации. `/leave` означает выход из комнаты, не сдачу боя.

Поля проверяются в конструкторах, некорректный ввод вызывает `ArgumentError`
без значения поля. Пустые значения, пробелы по краям, `|`, управляющие символы
C0/C1 и Unicode-разделители строк U+2028/U+2029 запрещены. В имени также запрещена
запятая; запятые внутри assertion сохраняются как часть оставшегося хвоста.
ID комнаты должен состоять из строчных ASCII-букв, цифр и дефисов (`[a-z0-9-]+`);
названия, URL и списки комнат не принимаются. Значения не обрезаются и не
нормализуются. Это ограничения нашего API; окончательные правила имён,
существование комнаты и права доступа проверяет сервер.

`toString()` команды не содержит её полей. Результат `serialize()` для `/trn`
содержит assertion и не предназначен для логирования.

Официальная документация: [Client-to-server messages](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#client-to-server-messages)
описывает оболочку и `/join`; [Global messages](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#global-messages)
описывает `/trn`. Разделение `/trn` по первым двум запятым также проверено в
[серверном обработчике `trn`](https://github.com/smogon/pokemon-showdown/blob/master/server/chat-commands/core.ts#L1609-L1617)
(ссылка на `master`, проверена 23 октября 2026 года).

Тесты: `flutter test test/core/protocol/client_commands_test.dart`.

## WebSocket-транспорт

`lib/core/transport/showdown_transport.dart` предоставляет `ShowdownTransport`
для Android/Linux на основе `web_socket_channel`. Он принимает WSS-адрес без
встроенных логина/пароля и фрагмента URL. Проверка TLS-сертификата стандартная;
небезопасный WS в рабочем адаптере не разрешён.

- `connect(Uri)` завершается после успешного handshake; одновременно допускается
  только одно подключение. Таймаут по умолчанию — 10 секунд.
- `status` содержит текущее состояние; `statuses` сообщает изменения:
  `disconnected`, `connecting`, `connected`, `disposed`.
- `messages` передаёт полные текстовые сообщения в исходном порядке, включая
  внутренние переносы строк. Декодирование протокола выполняет следующий слой.
- `send(ClientCommand)` отправляет сериализованную команду только в состоянии
  `connected`. Успех вызова не подтверждает принятие команды сервером.
- `failures` сообщает `TransportException` с категорией ошибки без исходного
  текста исключения или содержимого сообщения. Ошибка подключения также
  завершает `connect()` исключением, которое вызывающий код должен обработать.
- `disconnect()` отменяет незавершённое подключение и закрывает канал; после него
  разрешён новый явный `connect()`. `dispose()` закрывает также потоки и запрещает
  дальнейшее подключение. Оба метода допускают повторный вызов.

На потоки нужно подписаться до `connect()`: они broadcast и не повторяют историю.
Отмена ожидающего `connect()` даёт `TransportFailure.cancelled`; ошибки URI или
таймаутов — `ArgumentError`, неверный порядок вызовов — `StateError`.
Удалённое закрытие, ошибка сети, бинарное сообщение или ошибка отправки переводят
транспорт в `disconnected`. Бинарные сообщения не преобразуются в текст.
Очереди команд и автоматического reconnect/retry нет. Запоздалые события старого
канала игнорируются. Рабочий адаптер использует WebSocket ping каждые 30 секунд
для обнаружения потери связи; закрытие ожидается не более 2 секунд на операцию.
Владельцу при завершении работы следует отменить свои подписки и вызвать `dispose()`.

Через `channelFactory` тесты подставляют управляемый канал или локальный сервер;
это точка внедрения тестового адаптера, не настройка приложения.
Тесты охватывают handshake, таймаут, отмену, разрывы, ошибки отправки, старые
события, освобождение ресурсов и обмен с локальным WebSocket-сервером.
Они не подключаются к публичному серверу и не проверяют живую авторизацию/TLS.
Android INTERNET permission добавлен в основной manifest для всех сборок.

Источники: [Showdown → Protocol](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#protocol),
[WebSocketChannel.ready](https://pub.dev/documentation/web_socket_channel/3.0.3/web_socket_channel/WebSocketChannel/ready.html)
и [IOWebSocketChannel.connect](https://pub.dev/documentation/web_socket_channel/3.0.3/io/IOWebSocketChannel/IOWebSocketChannel.connect.html).
Контракт адаптера также проверен по исходникам установленной версии 3.0.3.

Проверка: `flutter test test/core/transport/showdown_transport_test.dart`.

## Маршрутизация событий комнат

`lib/core/rooms/room_router.dart` связывает транспорт, парсер и декодер.
Создавайте `RoomRouter(transport)` до подключения. Маршрутизатор использует новый
поток `transport.updates`: сообщения и смены статуса проходят в едином порядке,
чтобы последние сообщения перед разрывом не сделали устаревшие комнаты свежими.
Прежние `messages`, `statuses` и `failures` транспорта остаются доступны.

- `globalEvents` передаёт события без ID комнаты; `roomEvents` передаёт `RoomEvent`
  с явным `roomId` и исходным декодированным `event`.
- `eventsForRoom(id)` фильтрует общий поток без отдельного контроллера на комнату.
- `rooms` — неизменяемый снимок реестра `Map<String, RoomInfo>`; `roomChanges`
  публикует новые снимки. `RoomInfo` содержит `id`, `type`, nullable `title` и
  `isStale`. Изменение реестра происходит до публикации соответствующего события.
- `init` создаёт или заменяет запись, сбрасывая старое название; `title` меняет
  название существующей комнаты; `deinit` удаляет её. Неизвестный тип комнаты
  сохраняется строкой, что не означает поддержку её игровых механик.
- События неизвестной комнаты передаются подписчикам, но только `init` создаёт
  запись. Повреждённые события не меняют реестр; пустые строки пропускаются.
- `init/title/deinit` без заголовка маршрутизируются в `lobby`; оригинальный
  `event.roomId` остаётся `null`. Остальные сообщения без заголовка идут в
  глобальный поток, откуда будущий слой может обрабатывать сообщения lobby.
  Явный заголовок комнаты определяет маршрут независимо от типа события.
- Разрыв и новая попытка соединения помечают записи устаревшими. Сам по себе
  успешный reconnect не обновляет их: нужен новый `init` каждой комнаты.
  `title` не снимает отметку устаревания. Старые снимки остаются неизменными.

Все потоки broadcast, без истории. Секреты и журналы событий в реестре не хранятся.
Вызов `router.dispose()` отменяет его подписку, помечает сохранённые комнаты
устаревшими и закрывает потоки; транспорт остаётся во владении вызывающего кода.
При завершении отмените свои подписки и закройте маршрутизатор, затем транспорт.
Состояние боя, поиск, отправка команд и автоматический повторный вход не входят
в этот модуль.

Правила оболочки и отсутствующего заголовка: [Server-to-client messages](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#server-to-client-messages).
Жизненный цикл комнат: [Room initialization](https://github.com/smogon/pokemon-showdown/blob/9b136a8c8cdb860a8ab96fa063f906604e352547/PROTOCOL.md#room-initialization)
и обработка `init/deinit` в [официальном клиенте](https://github.com/smogon/pokemon-showdown-client/blob/master/play.pokemonshowdown.com/src/client-main.ts).
Правила снимков и устаревания — контракт нашего клиента.

Проверка: `flutter test test/core/rooms/room_router_test.dart`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## GitHub Actions

### Проверки pull request

Workflow **Flutter CI** запускается при открытии PR, добавлении коммитов и
повторном открытии PR. Сначала выполняются проверки форматирования, анализ кода
и тесты. После их успешного завершения параллельно собираются debug-версии
Android и Linux. При новых коммитах устаревший запуск этого PR отменяется.
Результаты и подробные журналы доступны во вкладке **Checks** у PR и в **Actions**.
Сборки проверяют компиляцию; эмулятор и проверка запуска интерфейса не выполняются.

Окружение: Ubuntu 24.04, Flutter 3.47.7 (Dart 3.13.5), Java Temurin 17,
Android SDK 36, Build Tools 36.0.0, NDK 28.2.13676358.

Локальные проверки из корня проекта:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
flutter build linux --debug
```

Проверка форматирования не меняет файлы. Чтобы исправить форматирование локально,
выполните `dart format .` и включите изменения в свой коммит.

### APK по ручному запросу

1. Добавьте workflow в основную ветку репозитория: это необходимо для появления
   кнопки ручного запуска.
2. Откройте **Actions → Build debug APK → Run workflow**.
3. Выберите ветку, содержащую workflow, и подтвердите запуск.
4. После успешного завершения откройте запуск и скачайте архив
   **debug-apk-<номер запуска>** в разделе **Artifacts**.
5. Распакуйте архив: внутри находится `app-debug.apk` для установки на Android.

Артефакт хранится 14 дней. Это универсальный debug APK с отладочной подписью,
не предназначенный для публикации в магазине. Секреты и production-ключ подписи
не требуются; GitHub Release автоматически не создаётся.
