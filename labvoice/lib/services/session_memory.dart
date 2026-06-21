import 'dart:convert';
import 'package:flutter/services.dart';

import '../models/session_state.dart';
import 'labvoice_api.dart';

class SessionMemory {
  static Future<SessionState> loadSessionState() async {
    try {
      final result = await LabVoiceApi.getSession();
      return SessionState.fromJson(result["session"]);
    } catch (_) {
      final jsonString = await rootBundle.loadString(
        'assets/data/session_state.json',
      );
      return SessionState.fromJson(json.decode(jsonString));
    }
  }
}
