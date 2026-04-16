import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:upsync_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('levanta la pantalla principal del ejemplo', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Upsync example'), findsOneWidget);
    expect(find.text('Aplicar y reiniciar'), findsOneWidget);
  });
}
