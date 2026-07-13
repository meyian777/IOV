import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/silent_trust_signals.dart';

void main() {
  const channel = MethodChannel('osvoz/session_auth');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads biometric availability without prompting authentication',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return call.method == 'canAuthenticate';
          });

      final signals = SilentTrustSignals(channel: channel);

      expect(await signals.biometricAvailable(), isTrue);
      expect(calls, ['canAuthenticate']);
    },
  );

  test(
    'simulated passkey and watch signals can be enabled for integration tests',
    () async {
      final signals = SilentTrustSignals(
        channel: channel,
        simulatedPasskey: true,
        simulatedWatchConfirmed: true,
      );

      expect(await signals.passkeyAvailable(), isTrue);
      expect(await signals.watchNearby(), isTrue);
      expect(await signals.watchUnlocked(), isTrue);
      expect(await signals.watchConfirmed(), isTrue);
    },
  );
}
