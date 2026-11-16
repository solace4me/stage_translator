// lib/services/incoming_files.dart
//
// Hymn files sent to the app from another app: "Open with" or "Share" on a
// .mxl / .musicxml file, e.g. the export of a sheet-music scanner. The Android
// side (MainActivity) reads the file; this hands it to the home screen.

import 'package:flutter/services.dart';

class IncomingFile {
  final String name;
  final Uint8List bytes;
  const IncomingFile(this.name, this.bytes);
}

class IncomingFiles {
  static const _channel = MethodChannel('stage_translator/files');

  /// Calls [onFile] for a file the app was opened with, and for every file
  /// sent while it is running.
  static void listen(void Function(IncomingFile file) onFile) {
    Future<void> take() async {
      try {
        final m = await _channel.invokeMapMethod<String, dynamic>('takeIncomingFile');
        final bytes = m?['bytes'];
        if (bytes is Uint8List) onFile(IncomingFile(m?['name'] as String? ?? 'file', bytes));
      } catch (_) {
        // other platforms: nothing to receive
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingFile') await take();
    });
    take();
  }
}
