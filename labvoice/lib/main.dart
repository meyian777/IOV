import 'package:flutter/material.dart';

import 'screens/labvoice_command_center.dart';

void main() {
  runApp(const LabVoiceApp());
}

class LabVoiceApp extends StatelessWidget {
  const LabVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LabVoice',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0E16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7568FF),
          brightness: Brightness.dark,
        ),
        fontFamily: "SF Pro Display",
        useMaterial3: true,
      ),
      home: const LabVoiceCommandCenter(),
    );
  }
}
