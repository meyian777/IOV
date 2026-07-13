import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/music_intent_parser.dart';

void main() {
  test('extrae artista despues de accion musical sin contaminar app', () {
    final intent = MusicIntentParser.parse(
      'abre VS Code y reproduce Banda Inventada en YouTube',
    );

    expect(intent, isNotNull);
    expect(intent!.query, 'banda inventada');
    expect(intent.platform, 'youtube');
  });

  test('entiende cualquier artista sin lista fija', () {
    final intent = MusicIntentParser.parse('pon Artista Libre 2040');

    expect(intent, isNotNull);
    expect(intent!.query, 'artista libre 2040');
    expect(intent.platform, 'youtube');
  });

  test('limpia conectores hablados antes del artista', () {
    final intent = MusicIntentParser.parse(
      'Abre Visual Studio Code y reproduce de Sonido Nuevo en español en YouTube',
    );

    expect(intent, isNotNull);
    expect(intent!.query, 'sonido nuevo en español');
    expect(intent.platform, 'youtube');
  });

  test('detecta plataforma explicita', () {
    final spotify = MusicIntentParser.parse('play Banda Solar on Spotify');
    final apple = MusicIntentParser.parse('pon Proyecto Lunar en Apple Music');

    expect(spotify!.query, 'banda solar');
    expect(spotify.platform, 'spotify');
    expect(apple!.query, 'proyecto lunar');
    expect(apple.platform, 'apple_music');
  });

  test('entiende abrir o buscar artista en plataforma musical', () {
    final openSpotify = MusicIntentParser.parse('abre Grupo Prisma en Spotify');
    final searchSpotify = MusicIntentParser.parse(
      'busca Sonido Libre en Spotify',
    );

    expect(openSpotify, isNotNull);
    expect(openSpotify!.query, 'grupo prisma');
    expect(openSpotify.platform, 'spotify');
    expect(searchSpotify, isNotNull);
    expect(searchSpotify!.query, 'sonido libre');
    expect(searchSpotify.platform, 'spotify');
  });

  test('detecta omision automatica de anuncios en youtube', () {
    final intent = MusicIntentParser.parse(
      'pon Artista Libre en YouTube y omite los anuncios',
    );

    expect(intent, isNotNull);
    expect(intent!.query, 'artista libre');
    expect(intent.platform, 'youtube');
    expect(intent.autoSkipAds, isTrue);
    expect(intent.toParameters()['auto_skip_ads'], 'true');
  });

  test('no inventa artista cuando solo se abre la plataforma', () {
    expect(MusicIntentParser.parse('abre Spotify'), isNull);
    expect(MusicIntentParser.parse('open Apple Music'), isNull);
  });

  test('no convierte comandos de apps en musica', () {
    expect(MusicIntentParser.parse('abre VS Code'), isNull);
    expect(MusicIntentParser.parse('abre terminal'), isNull);
  });
}
