class MusicIntent {
  final String query;
  final String platform;
  final bool explicitPlatform;
  final bool autoSkipAds;

  const MusicIntent({
    required this.query,
    required this.platform,
    required this.explicitPlatform,
    required this.autoSkipAds,
  });

  Map<String, String> toParameters() => {
    "query": query,
    "platform": platform,
    "explicit_platform": explicitPlatform.toString(),
    "auto_skip_ads": autoSkipAds.toString(),
  };
}

class MusicIntentParser {
  static const _defaultPlatform = "youtube";

  static MusicIntent? parse(String command) {
    final normalized = _normalize(command);
    final platform = _detectPlatform(normalized);
    final actionIndex =
        _firstMusicActionIndex(normalized) ??
        (platform == null ? null : _firstPlatformSearchActionIndex(normalized));
    if (actionIndex == null) return null;

    final afterAction = normalized.substring(actionIndex).trim();
    final query = _extractQuery(afterAction);
    if (query == null || query.isEmpty) return null;

    return MusicIntent(
      query: query,
      platform: platform ?? _defaultPlatform,
      explicitPlatform: platform != null,
      autoSkipAds: _requestsAdSkipping(normalized),
    );
  }

  static String _normalize(String command) {
    return command
        .toLowerCase()
        .replaceAll("á", "a")
        .replaceAll("é", "e")
        .replaceAll("í", "i")
        .replaceAll("ó", "o")
        .replaceAll("ú", "u")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();
  }

  static String? _detectPlatform(String text) {
    if (text.contains("spotify") || text.contains("spotyfy")) {
      return "spotify";
    }
    if (text.contains("apple music") ||
        text.contains("ipple music") ||
        text.contains("musica de apple")) {
      return "apple_music";
    }
    if (text.contains("youtube") || text.contains("you tube")) {
      return "youtube";
    }
    return null;
  }

  static int? _firstMusicActionIndex(String text) {
    final patterns = [
      RegExp(r'\b(reproduce|ponme|pon|toca|escuchar|quiero escuchar)\b'),
      RegExp(r'\b(play|listen to)\b'),
      RegExp(r'\b(musica de|cancion de|canciones de|song by|music by)\b'),
    ];
    int? best;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      if (best == null || match.start < best) best = match.start;
    }
    return best;
  }

  static int? _firstPlatformSearchActionIndex(String text) {
    final patterns = [
      RegExp(r'\b(abre|abrir|busca|buscar)\b'),
      RegExp(r'\b(open|search|find)\b'),
    ];
    int? best;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      if (best == null || match.start < best) best = match.start;
    }
    return best;
  }

  static String? _extractQuery(String text) {
    var cleaned = text;
    final prefixes = [
      "quiero escuchar",
      "listen to",
      "reproduce",
      "buscar",
      "busca",
      "abrir",
      "abre",
      "search",
      "find",
      "open",
      "ponme",
      "pon",
      "toca",
      "escuchar",
      "play",
      "musica de",
      "canciones de",
      "cancion de",
      "music by",
      "song by",
      "una cancion de",
      "una canción de",
      "cualquier cancion de",
      "cualquier canción de",
      "cualquier tema de",
      "cualquier musica de",
      "cualquier música de",
      "any song by",
      "any music by",
    ];
    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
        break;
      }
    }
    for (final prefix in const [
      "una cancion de",
      "una canción de",
      "cualquier cancion de",
      "cualquier canción de",
      "cualquier tema de",
      "cualquier musica de",
      "cualquier música de",
      "cancion de",
      "canción de",
      "musica de",
      "música de",
      "music by",
      "song by",
    ]) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
        break;
      }
    }

    cleaned = cleaned
        .replaceFirst(RegExp(r'^(de|by)\s+'), "")
        .replaceAll(
          RegExp(
            r'\b(en|por|con)\s+(youtube|you tube|spotify|spotyfy|apple music|ipple music)\b',
          ),
          "",
        )
        .replaceAll(
          RegExp(r'\b(on|with)\s+(youtube|you tube|spotify|apple music)\b'),
          "",
        )
        .replaceAll(
          RegExp(
            r'\b(y|and)\s+(abre|open|dime|dame|give|tell|continua|continue).*$',
          ),
          "",
        )
        .replaceAll(RegExp(r'\b(dime|dame|give|tell)\s+.*$'), "")
        .replaceAll(
          RegExp(
            r'\b(y|and)?\s*(omite|omitir|quita|quitar|skip)\s+(los\s+|the\s+)?(anuncios|anuncio|ads|ad).*$',
          ),
          "",
        )
        .replaceAll(RegExp(r'\bsin\s+anuncios\b'), "")
        .replaceAll(RegExp(r'^[\s,.:;!?-]+|[\s,.:;!?-]+$'), "")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();

    final nonMusic = {
      "visual studio code",
      "vs code",
      "terminal",
      "navegador",
      "browser",
      "youtube",
      "spotify",
      "apple music",
    };
    if (cleaned.isEmpty || nonMusic.contains(cleaned)) return null;
    return cleaned;
  }

  static bool looksLikeMusicRequest(String command) {
    final text = _normalize(command);
    return _detectPlatform(text) != null ||
        text.contains("cancion") ||
        text.contains("canción") ||
        text.contains("musica") ||
        text.contains("música") ||
        text.contains("artista") ||
        text.contains("song") ||
        text.contains("music") ||
        text.contains("artist");
  }

  static bool _requestsAdSkipping(String text) =>
      text.contains("omite anuncios") ||
      text.contains("omite los anuncios") ||
      text.contains("omitir anuncios") ||
      text.contains("omitir los anuncios") ||
      text.contains("quita anuncios") ||
      text.contains("quita los anuncios") ||
      text.contains("sin anuncios") ||
      text.contains("skip ads") ||
      text.contains("skip the ads") ||
      text.contains("skip ad");
}
