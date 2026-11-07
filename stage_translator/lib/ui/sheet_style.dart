// lib/ui/sheet_style.dart

import 'package:flutter/material.dart';

/// Monospace style shared by the editors, so chords stay above their words.
/// DejaVu Sans Mono is bundled (assets/fonts) because it draws the flat sign
/// at the same width as a letter; system mono fonts often don't have it.
const TextStyle kSheetTextStyle = TextStyle(
  fontFamily: 'DejaVuSansMono',
  height: 1.35,
);

/// Width of one DejaVu Sans Mono character as a share of the font size
/// (1233 / 2048 units).
const double kMonoCharWidth = 0.602;
