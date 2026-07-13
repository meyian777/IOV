import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/session_authenticator.dart';

void main() {
  test('detecta inicio de sesion por voz en español e ingles', () {
    expect(
      MethodChannelSessionAuthenticator.validatesSessionStart(
        'OSvoz inicia mi sesión',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesSessionStart(
        'IOV inicia mi sesión',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesSessionStart(
        'start my session',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesSessionStart('sign me in'),
      isTrue,
    );
  });

  test('rechaza frases sin intencion de iniciar sesion', () {
    expect(
      MethodChannelSessionAuthenticator.validatesSessionStart(
        'pon musica en youtube',
      ),
      isFalse,
    );
  });

  test('acepta autorizacion en español aunque OSvoz se transcriba como Os', () {
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'Os autorizo esta sesión',
      ),
      isTrue,
    );
  });

  test('acepta frases naturales de autorizacion en español e ingles', () {
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'autorizo la sesión',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'OSvoz, autorizo esta sesion',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'IOV, autorizo esta sesion',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'OSvoz I authorize this session',
      ),
      isTrue,
    );
  });

  test('acepta autorizacion corta si el audio se corta temprano', () {
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'autorizo esta',
      ),
      isTrue,
    );
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'I authorize',
      ),
      isTrue,
    );
  });

  test('rechaza frases sin intencion de autorizacion', () {
    expect(
      MethodChannelSessionAuthenticator.validatesVoiceAuthorization(
        'hola sistema',
      ),
      isFalse,
    );
  });
}
