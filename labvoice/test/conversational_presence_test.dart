import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/conversational_presence.dart';

void main() {
  test('diagnostics cue tells the user what will happen', () {
    final cue = ConversationalPresence.cue(
      stage: ConversationalPresenceStage.received,
      actionName: 'RUN_DIAGNOSTICS',
      language: 'es',
    );

    expect(cue, contains('pruebas'));
    expect(cue, contains('esencial'));
  });

  test('open app cue stays short and natural', () {
    final cue = ConversationalPresence.cue(
      stage: ConversationalPresenceStage.received,
      actionName: 'OPEN_VSCODE',
      language: 'es',
    );

    expect(cue.length, lessThan(40));
  });

  test('progress messages rotate for long running actions', () {
    final messages = ConversationalPresence.progressMessages(
      actionName: 'RUN_DIAGNOSTICS',
      language: 'es',
    );

    expect(messages, hasLength(greaterThan(1)));
    expect(messages.toSet(), hasLength(messages.length));
  });

  test('security cue prepares the user before local auth appears', () {
    final cue = ConversationalPresence.cue(
      stage: ConversationalPresenceStage.securityCheck,
      actionName: 'RUN_DIAGNOSTICS',
      language: 'es',
    );

    expect(cue, contains('confirmo'));
  });
}
