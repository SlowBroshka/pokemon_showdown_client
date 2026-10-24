import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/main.dart';

void main() {
  testWidgets('starts disconnected with no automatic network request', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Статус: отключено'), findsOneWidget);
    expect(find.text('Активной комнаты нет.'), findsOneWidget);
    final join = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Войти'),
    );
    expect(join.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
