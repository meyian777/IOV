import 'dart:convert';
import 'dart:io';

abstract class LocalSessionTrustStore {
  Future<bool> isTrusted();
  Future<void> trustFor(Duration duration);
  Future<void> clear();
}

class FileLocalSessionTrustStore implements LocalSessionTrustStore {
  FileLocalSessionTrustStore({File? file}) : _file = file ?? _defaultFile();

  final File _file;

  @override
  Future<bool> isTrusted() async {
    try {
      if (!await _file.exists()) return false;
      final data = jsonDecode(await _file.readAsString());
      if (data is! Map<String, dynamic>) return false;
      final expiresAt = DateTime.tryParse(data["expires_at"]?.toString() ?? "");
      if (expiresAt == null) return false;
      final trusted = DateTime.now().toUtc().isBefore(expiresAt.toUtc());
      if (!trusted) await clear();
      return trusted;
    } catch (_) {
      await clear();
      return false;
    }
  }

  @override
  Future<void> trustFor(Duration duration) async {
    final expiresAt = DateTime.now().toUtc().add(duration);
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({"trusted": true, "expires_at": expiresAt.toIso8601String()}),
    );
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  static File _defaultFile() {
    final home = Platform.environment["HOME"];
    final base = home == null || home.isEmpty
        ? Directory.systemTemp.path
        : "$home/Library/Application Support";
    return File("$base/OSvoz/session_trust.json");
  }
}
