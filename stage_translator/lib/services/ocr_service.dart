// lib/services/ocr_service.dart
//
// The only file that touches ML Kit. It converts ML Kit's blocks/lines/elements
// into plain OcrWord boxes and hands them to the pure-Dart LayoutRebuilder.

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/layout_rebuilder.dart';

class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Reads an image file and returns the sheet as aligned plain text.
  Future<String> readSheet(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);

    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final words = <OcrWord>[];
        for (final e in line.elements) {
          final r = e.boundingBox;
          words.add(OcrWord(e.text, r.left, r.top, r.right, r.bottom));
        }
        if (words.isNotEmpty) lines.add(OcrLine(words));
      }
    }
    return LayoutRebuilder.rebuild(lines);
  }

  Future<void> dispose() => _recognizer.close();
}
