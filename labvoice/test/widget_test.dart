import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/main.dart';

void main() {
  testWidgets('LabVoice inicia correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const LabVoiceApp());

    expect(find.text('LABVOICE DEV COMMAND CENTER'), findsOneWidget);
  });
}
