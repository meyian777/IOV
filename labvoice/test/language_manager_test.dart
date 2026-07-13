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

  test('spoken Spanish can override an English session profile', () {
    LanguageManager.setLanguage('en_US');

    expect(
      LanguageManager.alignToText('Dame el estado del sistema en detalle'),
      'es',
    );
    expect(LanguageManager.current.languageTag, 'es');
    expect(LanguageManager.activeVoiceLocale, 'es-ES');
  });

  test('automatic mode keeps long YouTube Spanish commands in Spanish', () {
    LanguageManager.setLanguage('auto');
    expect(LanguageManager.alignToText('Show me the most important'), 'en');

    expect(
      LanguageManager.alignToText(
        'abre el navegador y reproduce en YouTube una canción de Banda Solar y dame un resumen',
      ),
      'es',
    );
    expect(LanguageManager.activeVoiceLocale, 'es-ES');
    expect(LanguageManager.activeSystemVoice, 'Reed (Spanish (Mexico))');
  });

  test('automatic mode recognizes short English transition words', () {
    LanguageManager.setLanguage('auto');

    expect(LanguageManager.alignToText('While'), 'en');
    expect(LanguageManager.activeRecognitionLocale, 'en_US');
  });

  test('explicit spoken language requests win immediately', () {
    LanguageManager.setLanguage('en_US');

    expect(LanguageManager.alignToText('IOV háblame en español'), 'es');
    expect(LanguageManager.activeVoiceLocale, 'es-ES');

    expect(LanguageManager.alignToText('IOV switch to English'), 'en');
    expect(LanguageManager.activeVoiceLocale, 'en-US');
  });

  test('automatic mode detects non Latin scripts', () {
    LanguageManager.setLanguage('auto');

    expect(LanguageManager.alignToText('こんにちは'), 'ja');
    expect(LanguageManager.activeVoiceLocale, 'ja-JP');
    expect(LanguageManager.alignToText('안녕하세요'), 'ko');
    expect(LanguageManager.activeVoiceLocale, 'ko-KR');
  });

  test('uses short confirmation prompt for sensitive actions', () {
    LanguageManager.setLanguage('es_ES');

    expect(
      LanguageManager.confirmationRequired('RUN_FLUTTER'),
      'Permiso para iniciar Flutter. Confirma: sí o no.',
    );

    LanguageManager.setLanguage('en_US');
    expect(
      LanguageManager.confirmationRequired('RUN_FLUTTER'),
      'Permission to start Flutter. Confirm: yes or no.',
    );
  });
}
