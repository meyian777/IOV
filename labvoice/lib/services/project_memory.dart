import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/project_state.dart';

class ProjectMemory {
  static Future<ProjectState> loadProjectState() async {
    final String jsonString =
        await rootBundle.loadString('assets/data/project_state.json');

    final Map<String, dynamic> jsonData =
        json.decode(jsonString);

    return ProjectState.fromJson(jsonData);
  }
}