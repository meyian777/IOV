import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/iov_interaction_state_machine.dart';
import 'package:labvoice/services/voice_control_router.dart';

void main() {
  group('VoiceControlRouter', () {
    final router = VoiceControlRouter();

    test('acepta controles dirigidos en español e inglés', () {
      expect(router.evaluate('Ok, detente').event, VoiceControlEvent.stop);
      expect(router.evaluate('IOV, pausa').event, VoiceControlEvent.pause);
      expect(router.evaluate('IOV, continúa').event, VoiceControlEvent.resume);
      expect(router.evaluate('Stop IOV').event, VoiceControlEvent.stop);
      expect(router.evaluate('IOV continue').event, VoiceControlEvent.resume);
    });

    test('requiere alta confianza para órdenes sin IOV u OK', () {
      expect(router.evaluate('pausa', confidence: 0.70).accepted, isFalse);
      expect(
        router.evaluate('pausa', confidence: 0.93).event,
        VoiceControlEvent.pause,
      );
    });

    test('no interpreta para como pausa', () {
      expect(router.evaluate('esto sirve para desarrollar').accepted, isFalse);
      expect(router.evaluate('para', confidence: 0.99).accepted, isFalse);
    });

    test('detecta variantes habituales de IOV para activar barge-in', () {
      expect(router.containsWakeWord('IOV'), isTrue);
      expect(router.containsWakeWord('I O V, pausa'), isTrue);
      expect(router.containsWakeWord('Yo vi detente'), isTrue);
      expect(router.containsWakeWord('eye oh vee stop'), isTrue);
      expect(router.containsWakeWord('continúa la explicación'), isFalse);
      expect(router.evaluate('Yo vi detente').event, VoiceControlEvent.stop);
    });
  });

  test(
    'máquina de estados pausa, reanuda y detiene con transiciones claras',
    () {
      final machine = IOVInteractionStateMachine();

      expect(machine.dispatch(IOVInteractionEvent.speak), isTrue);
      expect(machine.state, IOVInteractionState.speaking);
      expect(machine.dispatch(IOVInteractionEvent.pause), isTrue);
      expect(machine.state, IOVInteractionState.paused);
      expect(machine.dispatch(IOVInteractionEvent.resume), isTrue);
      expect(machine.state, IOVInteractionState.speaking);
      expect(machine.dispatch(IOVInteractionEvent.stop), isTrue);
      expect(machine.state, IOVInteractionState.idle);
    },
  );
}
