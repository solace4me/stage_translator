import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/services/pad_player.dart';

void main() {
  test('a pad loop exists for every key, in both versions', () {
    for (var s = 0; s < 12; s++) {
      for (final light in [false, true]) {
        final path = PadEngine.assetFor(s, light: light);
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: path);
        expect(f.lengthSync(), greaterThan(50000), reason: path);
      }
    }
  });

  test('keys wrap around the octave', () {
    expect(PadEngine.assetFor(7, light: false), 'assets/pads/warm_full_07.ogg');
    expect(PadEngine.assetFor(14, light: true), 'assets/pads/warm_light_02.ogg');
  });
}
