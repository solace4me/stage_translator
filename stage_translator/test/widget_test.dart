// The default Flutter counter test referred to a MyApp that does not exist in
// this project. This checks the app's built-in tone maker instead.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/services/tone_player.dart';

void main() {
  group('ToneSynth', () {
    test('writes a valid 16-bit mono WAV', () {
      final wav = ToneSynth.wav(ToneSynth.doh(7)); // Doh = G
      final d = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(d.getUint16(22, Endian.little), 1); // mono
      expect(d.getUint32(24, Endian.little), ToneSynth.sampleRate);
      expect(d.getUint32(40, Endian.little), wav.length - 44);
      expect(wav.length, greaterThan(44 + ToneSynth.sampleRate)); // over a second
    });

    test('never clips', () {
      final wav = ToneSynth.wav(ToneSynth.rolled([43, 55, 62, 71]));
      final d = ByteData.sublistView(wav);
      var peak = 0;
      for (var i = 44; i < wav.length; i += 2) {
        final v = d.getInt16(i, Endian.little).abs();
        if (v > peak) peak = v;
      }
      expect(peak, inInclusiveRange(20000, 32767));
    });

    test('Doh sits in the octave from middle C', () {
      expect(ToneSynth.doh(0).single.midi, 60); // C
      expect(ToneSynth.doh(11).single.midi, 71); // B
      expect(ToneSynth.dohChord(2).map((n) => n.midi), [62, 66, 69, 74]); // D F# A D
      expect(ToneSynth.frequency(69), closeTo(440, 1e-9));
    });

    test('starting notes roll from the lowest', () {
      expect(ToneSynth.rolled([67, 48, 60]).map((n) => n.midi), [48, 60, 67]);
    });
  });
}
