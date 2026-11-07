// lib/main.dart
//
// Stage Translator Pro: chord sheet -> movable-do solfège.
//
// Flow: Library -> Scan (camera / gallery / paste) -> Review raw OCR text
//       -> Sheet editor (pick Doh, edit, save, export PDF)

import 'package:flutter/material.dart';

import 'ui/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StageTranslatorApp());
}

class StageTranslatorApp extends StatelessWidget {
  const StageTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stage Translator Pro',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // stage lighting: dark by default
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}

