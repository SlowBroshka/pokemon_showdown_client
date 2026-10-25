import 'dart:async';

import 'package:flutter/material.dart';

import 'core/session/showdown_session.dart';
import 'core/auth/auth_controller.dart';
import 'features/connection/connection_controller.dart';

import 'app_config.dart';
import 'l10n/app_localizations.dart';

import 'features/connection/connection_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.locale = appLocale});
  final Locale locale;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ShowdownSession _session;
  late final AuthController _authController;
  late final ConnectionController _controller;

  @override
  void initState() {
    super.initState();
    // Both live above the screen, so replacing a screen does not close the socket.
    _session = ShowdownSession();
    _authController = AuthController(session: _session);
    _controller = ConnectionController(session: _session);
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_closeSession());
    super.dispose();
  }

  Future<void> _closeSession() async {
    await _authController.dispose();
    await _controller.closed;
    await _session.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: widget.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      inputDecorationTheme: const InputDecorationTheme(filled: true),
    ),
    home: ConnectionScreen(
      controller: _controller,
      authController: _authController,
    ),
  );
}
