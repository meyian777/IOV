import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/language_manager.dart';

void main() {
  tearDown(() {
    LanguageManager.setLanguage('es_ES');
  });

  test('keeps recognition, voice and response language aligned', () {
    LanguageManager.setLanguage('es_ES');

    expect(LanguageManager.current.recognitionLocale, 'es_ES');
    expect(LanguageManager.current.voiceLocale, 'es-ES');
    expect(LanguageManager.current.languageTag, 'es');
    expect(LanguageManager.languageUpdated(), contains('Idioma'));
  });

  test('supports English as a complete profile', () {
    LanguageManager.setLanguage('en_US');

    expect(LanguageManager.current.voiceLocale, 'en-US');
    expect(LanguageManager.current.languageTag, 'en');
    expect(LanguageManager.languageUpdated(), contains('Language'));
  });
}
