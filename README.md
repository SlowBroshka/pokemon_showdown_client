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
