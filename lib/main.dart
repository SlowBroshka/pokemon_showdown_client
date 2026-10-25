import 'package:flutter/material.dart';

import 'app_config.dart';
import 'l10n/app_localizations.dart';

import 'features/connection/connection_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.locale = appLocale});
  final Locale locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      inputDecorationTheme: const InputDecorationTheme(filled: true),
    ),
    home: const ConnectionScreen(),
  );
}
