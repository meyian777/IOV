import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/language_manager.dart';

void main() {
  tearDown(() {
    LanguageManager.setLanguage('auto');
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

  test('presents the founder identity in Spanish and English', () {
    LanguageManager.setLanguage('es_ES');
    expect(
      LanguageManager.creatorIdentity(),
      contains('Ian Faber Mendoza Mey'),
    );
    expect(LanguageManager.creatorIdentity(), contains('fundador'));
    expect(LanguageManager.founderBiography(), contains('Sincelejo'));

    LanguageManager.setLanguage('en_US');
    expect(
      LanguageManager.creatorIdentity(),
      contains('Ian Faber Mendoza Mey'),
    );
    expect(LanguageManager.creatorIdentity(), contains('founder'));
    expect(LanguageManager.founderBiography(), contains('visual disabilities'));
  });

  test('automatic mode detects English and Spanish text', () {
    LanguageManager.setLanguage('auto');

    expect(LanguageManager.activeRecognitionLocale, 'es_ES');
    expect(LanguageManager.alignToText('Open the project and run tests'), 'en');
    expect(LanguageManager.activeRecognitionLocale, 'en_US');
    expect(LanguageManager.activeVoiceLocale, 'en-US');

    expect(
      LanguageManager.alignToText('Abre el proyecto y ejecuta las pruebas'),
      'es',
    );
    expect(LanguageManager.activeVoiceLocale, 'es-ES');
  });

  test('automatic mode recognizes short English transition words', () {
    LanguageManager.setLanguage('auto');

    expect(LanguageManager.alignToText('While'), 'en');
    expect(LanguageManager.activeRecognitionLocale, 'en_US');
  });

  test('automatic mode detects non Latin scripts', () {
    LanguageManager.setLanguage('auto');

    expect(LanguageManager.alignToText('こんにちは'), 'ja');
    expect(LanguageManager.activeVoiceLocale, 'ja-JP');
    expect(LanguageManager.alignToText('안녕하세요'), 'ko');
    expect(LanguageManager.activeVoiceLocale, 'ko-KR');
  });
}
