import 'dart:async';

import 'package:flutter/material.dart';

import 'core/session/showdown_session.dart';
import 'core/matchmaking/formats/format_catalog_controller.dart';
import 'core/auth/auth_controller.dart';
import 'features/connection/connection_controller.dart';
import 'features/matchmaking/matchmaking_controller.dart';

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
  late final FormatCatalogController _formatCatalog;
  late final ConnectionController _controller;
  late final MatchmakingController _matchmaking;

  @override
  void initState() {
    super.initState();
    // Controllers live above the screen and share the app-owned session.
    _session = ShowdownSession();
    _formatCatalog = FormatCatalogController(session: _session);
    _authController = AuthController(session: _session);
    _controller = ConnectionController(session: _session);
    _matchmaking = MatchmakingController(
      session: _session,
      auth: _authController,
      catalog: _formatCatalog,
      rooms: _controller.rooms,
    );
  }

  @override
  void dispose() {
    unawaited(_closeSession());
    super.dispose();
  }

  Future<void> _closeSession() async {
    await _matchmaking.dispose();
    _controller.dispose();
    await _formatCatalog.dispose();
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
      matchmakingController: _matchmaking,
    ),
  );
}
