class SessionState {
  final String currentGoal;
  final String currentTask;
  final String lastAction;
  final String nextAction;
  final String workingMode;
  final String activeProject;

  SessionState({
    required this.currentGoal,
    required this.currentTask,
    required this.lastAction,
    required this.nextAction,
    required this.workingMode,
    required this.activeProject,
  });

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      currentGoal: json['current_goal'] ?? '',
      currentTask: json['current_task'] ?? '',
      lastAction: json['last_action'] ?? '',
      nextAction: json['next_action'] ?? '',
      workingMode: json['working_mode'] ?? '',
      activeProject: json['active_project'] ?? '',
    );
  }
}