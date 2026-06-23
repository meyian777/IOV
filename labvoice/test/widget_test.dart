import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/main.dart';

void main() {
  testWidgets('LabVoice inicia correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const LabVoiceApp());

    expect(find.text('LABVOICE'), findsOneWidget);
    expect(find.byKey(const Key('voice-core')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });
}
