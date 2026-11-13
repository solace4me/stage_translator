// lib/services/tone_player.dart
//
// "Play do": a short piano-like tone so you can find Doh (or the starting
// notes of a hymn) before you begin. The sound is made in code, so there are
// no sound files to ship: a few harmonics with a soft attack and a decay,
// written as a small WAV file in the temp folder and played with audioplayers.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// One note: MIDI number (60 = middle C) and when it starts, in seconds.
typedef ToneNote = ({int midi, double start});

class ToneSynth {
  static const sampleRate = 22050;
  static const _harmonics = [1.0, 0.45, 0.22, 0.12, 0.06];

  static double frequency(int midi) => 440.0 * math.pow(2, (midi - 69) / 12);

  /// 16-bit mono WAV bytes with every note mixed in.
  static Uint8List wav(List<ToneNote> notes, {double noteLength = 1.8}) {
    if (notes.isEmpty) return _header(0);
    final lastStart = notes.map((n) => n.start).reduce(math.max);
    final total = ((lastStart + noteLength) * sampleRate).ceil();
    final mix = Float64List(total);
    final len = (noteLength * sampleRate).round();
    const fade = 600; // samples of fade-out at the end, so it never clicks

    for (final n in notes) {
      final f = frequency(n.midi);
      final s0 = (n.start * sampleRate).round();
      for (var i = 0; i < len && s0 + i < total; i++) {
        final t = i / sampleRate;
        var env = math.min(1.0, t / 0.006) * math.exp(-2.6 * t);
        if (i > len - fade) env *= (len - i) / fade;
        var v = 0.0;
        for (var k = 0; k < _harmonics.length; k++) {
          final fk = f * (k + 1);
          if (fk >= sampleRate / 2) break;
          v += _harmonics[k] * math.exp(-k * 1.3 * t) * math.sin(2 * math.pi * fk * t);
        }
        mix[s0 + i] += v * env;
      }
    }

    var peak = 1e-9;
    for (final v in mix) {
      if (v.abs() > peak) peak = v.abs();
    }
    final gain = 0.8 * 32767 / peak;
    final bytes = _header(total);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < total; i++) {
      data.setInt16(44 + i * 2, (mix[i] * gain).round().clamp(-32768, 32767).toInt(), Endian.little);
    }
    return bytes;
  }

  static Uint8List _header(int samples) {
    final bytes = Uint8List(44 + samples * 2);
    final d = ByteData.sublistView(bytes);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes[at + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    d.setUint32(4, 36 + samples * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    d.setUint32(16, 16, Endian.little); // fmt chunk size
    d.setUint16(20, 1, Endian.little); // PCM
    d.setUint16(22, 1, Endian.little); // mono
    d.setUint32(24, sampleRate, Endian.little);
    d.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    d.setUint16(32, 2, Endian.little); // block align
    d.setUint16(34, 16, Endian.little); // bits per sample
    ascii(36, 'data');
    d.setUint32(40, samples * 2, Endian.little);
    return bytes;
  }

  // ------------------------------------------------------------ what to play

  /// Doh in the octave around middle C (C4 up to B4).
  static int dohMidi(int dohSemitone) => 60 + dohSemitone % 12;

  /// d, then d m s d' as a broken chord.
  static List<ToneNote> doh(int dohSemitone) => [(midi: dohMidi(dohSemitone), start: 0.0)];

  static List<ToneNote> dohChord(int dohSemitone) {
    final d = dohMidi(dohSemitone);
    return [
      for (final (i, step) in [0, 4, 7, 12].indexed) (midi: d + step, start: i * 0.32),
    ];
  }

  /// Starting notes of the voices, lowest first, quickly rolled.
  static List<ToneNote> rolled(List<int> midis) {
    final sorted = [...midis]..sort();
    return [for (final (i, m) in sorted.indexed) (midi: m, start: i * 0.12)];
  }
}

class TonePlayer {
  static AudioPlayer? _player;

  /// Plays [notes]. Each different sound is made once and kept in the temp
  /// folder, so pressing the button again starts at once.
  static Future<void> play(List<ToneNote> notes) async {
    if (notes.isEmpty) return;
    final name = notes.map((n) => '${n.midi}-${(n.start * 100).round()}').join('_');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tone_$name.wav');
    if (!await file.exists()) await file.writeAsBytes(ToneSynth.wav(notes), flush: true);
    final player = _player ??= AudioPlayer();
    await player.stop();
    await player.play(DeviceFileSource(file.path));
  }
}
