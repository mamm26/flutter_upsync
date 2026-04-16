import 'package:flutter_test/flutter_test.dart';

import 'package:upsync_example/main.dart';

void main() {
  testWidgets('muestra los controles base del ejemplo', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Upsync example'), findsOneWidget);
    expect(find.text('Iniciar upsync'), findsOneWidget);
    expect(find.text('Revisar ahora'), findsOneWidget);
    expect(find.text('Manifest URL'), findsOneWidget);
  });
}
