import '../models/session_state.dart';

class SessionMemory {
  static Future<SessionState> loadSessionState() async {
    return SessionState(
      currentGoal: "Build LabVoice OS",
      currentTask: "Design Session Manager",
      lastAction: "Implement Project Memory",
      nextAction: "Create Session Memory",
      workingMode: "developer",
      activeProject: "LabVoice",
    );
  }
}