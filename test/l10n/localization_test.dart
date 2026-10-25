import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/main.dart';
import 'package:pokemon_showdown_client/l10n/app_localizations.dart';
import 'package:pokemon_showdown_client/features/connection/connection_message.dart';
import 'package:pokemon_showdown_client/features/connection/connection_message_localization.dart';

void main() {
  test('all supported ARB files have complete, nonempty translations', () {
    final template = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final keys = template.keys.where((key) => !key.startsWith('@')).toSet();
    for (final locale in AppLocalizations.supportedLocales) {
      final translations = jsonDecode(
        File('lib/l10n/app_${locale.languageCode}.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        translations.keys.where((key) => !key.startsWith('@')).toSet(),
        keys,
      );
      for (final key in keys) {
        expect(translations[key], isA<String>());
        expect(
          (translations[key] as String).trim(),
          isNotEmpty,
          reason: '${locale.languageCode}: $key',
        );
      }
    }
  });

  for (final language in ['ru', 'en']) {
    testWidgets('$language localizes errors, notices and narrow layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locale = Locale(language);
      final l10n = await AppLocalizations.delegate.load(locale);
      await tester.pumpWidget(MyApp(locale: locale));
      await tester.pumpAndSettle();
      expect(find.text(l10n.statusDisconnected), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, l10n.serverAddress),
        'https://invalid.test',
      );
      await tester.tap(find.text(l10n.connect));
      await tester.pumpAndSettle();
      expect(find.text(l10n.invalidWssAddress), findsWidgets);
      await tester.scrollUntilVisible(
        find.text(l10n.noticesHeading),
        300,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(find.text(l10n.invalidWssAddress), findsWidgets);
      expect(tester.takeException(), isNull);
      for (final message in ConnectionMessage.values) {
        expect(localizeConnectionMessage(message, l10n), isNotEmpty);
      }
      expect(l10n.roomIdValue('battle-gen9-123'), contains('battle-gen9-123'));
      expect(
        l10n.roomType('chat'),
        language == 'ru' ? 'Тип: чат' : 'Type: chat',
      );
      expect(
        l10n.roomType('unknown'),
        language == 'ru' ? 'Тип: другой' : 'Type: other',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('Russian remains default on an English device', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Подключиться'), findsOneWidget);
    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('ru'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
