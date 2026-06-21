class ProjectState {
  final String project;
  final String lastTask;
  final String nextTask;
  final String lastFile;
  final String status;
  final String owner;
  final String version;

  ProjectState({
    required this.project,
    required this.lastTask,
    required this.nextTask,
    required this.lastFile,
    required this.status,
    required this.owner,
    required this.version,
  });

  factory ProjectState.fromJson(Map<String, dynamic> json) {
    return ProjectState(
      project: json['project'] ?? '',
      lastTask: json['last_task'] ?? '',
      nextTask: json['next_task'] ?? '',
      lastFile: json['last_file'] ?? '',
      status: json['status'] ?? '',
      owner: json['owner'] ?? '',
      version: json['version'] ?? '',
    );
  }
}