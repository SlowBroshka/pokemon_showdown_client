import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/main.dart';

void main() {
  testWidgets('starts disconnected with no automatic network request', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Статус: отключено'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Активной комнаты нет.'),
      250,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.text('Активной комнаты нет.'), findsOneWidget);
    final join = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Войти'),
    );
    expect(join.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
