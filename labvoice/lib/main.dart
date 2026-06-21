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
      title: 'LABVOICE DEV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LabVoiceCommandCenter(),
    );
  }
}
