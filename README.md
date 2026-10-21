# pokemon_showdown_client

A new Flutter project.

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
