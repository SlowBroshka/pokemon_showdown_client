import 'package:flutter/material.dart';

import 'features/connection/connection_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pokémon Showdown',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      inputDecorationTheme: const InputDecorationTheme(filled: true),
    ),
    home: const ConnectionScreen(),
  );
}
