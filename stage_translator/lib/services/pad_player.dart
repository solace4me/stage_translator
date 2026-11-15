// lib/services/pad_player.dart
//
// Worship pad: a soft sustained sound in the song's key, under the band, in
// prayer and between songs. One pad plays for the whole app, so it keeps going
// from song to song in a set and glides (crossfades) into each new key.
//
// Sounds: assets/pads/warm_<full|light>_<00..11>.ogg, seamless 40 s loops made
// for this app (tool/render_pads.py). 00 = C, 01 = C#/D♭ ... 11 = B.
// "full" has the low end, for a mixer or a big speaker; "light" sits higher so
// it still sounds full on a phone speaker. Auto picks by what is plugged in.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

enum PadVoicing { auto, full, light }

/// Asks Android whether sound is coming out of the phone's own speaker.
class AudioOutput {
  static const _channel = MethodChannel('stage_translator/audio');

  static Future<bool> isPhoneSpeaker() async {
    try {
      return await _channel.invokeMethod<bool>('outputIsPhoneSpeaker') ?? false;
    } catch (_) {
      return false; // other platforms: assume a proper speaker
    }
  }
}

class PadEngine extends ChangeNotifier {
  static final PadEngine instance = PadEngine._();
  PadEngine._();

  static const _fadeIn = Duration(milliseconds: 3000);
  static const _glide = Duration(milliseconds: 3500); // key change crossfade
  static const _fadeOut = Duration(milliseconds: 2500);

  final List<AudioPlayer> _players = [
    AudioPlayer(handleInterruptions: false),
    AudioPlayer(handleInterruptions: false),
  ];
  int _active = 0;
  int _gen = 0; // bumps on every command, so an older fade stops itself

  bool _on = false;
  int? _key;
  double _volume = 0.7;
  PadVoicing _voicing = PadVoicing.auto;
  bool _usingLight = false;

  bool get isPlaying => _on;
  int? get key => _key;
  double get volume => _volume;
  PadVoicing get voicing => _voicing;

  /// True when the light (phone speaker) version is playing.
  bool get usingLight => _usingLight;

  static String assetFor(int semitone, {required bool light}) =>
      'assets/pads/warm_${light ? 'light' : 'full'}_${(semitone % 12).toString().padLeft(2, '0')}.ogg';

  Future<void> toggle(int semitone) => _on ? stop() : start(semitone);

  Future<void> start(int semitone) async {
    _on = true;
    _key = semitone % 12;
    notifyListeners();
    await _crossfadeTo(_key!, _fadeIn);
  }

  Future<void> stop() async {
    if (!_on) return;
    _on = false;
    notifyListeners();
    final gen = ++_gen;
    final p = _players[_active];
    final from = p.volume;
    await _ramp(gen, _fadeOut, (x) => p.setVolume(from * math.cos(x * math.pi / 2)));
    if (gen != _gen) return;
    for (final pl in _players) {
      await pl.stop();
    }
  }

  /// Called by each song screen with its key. While playing, glides to it.
  void follow(int semitone) {
    final s = semitone % 12;
    if (!_on) {
      _key = s;
      return;
    }
    if (s == _key) return;
    _key = s;
    notifyListeners();
    _crossfadeTo(s, _glide);
  }

  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    if (_on) _players[_active].setVolume(_volume);
    notifyListeners();
  }

  void setVoicing(PadVoicing v) {
    if (v == _voicing) return;
    _voicing = v;
    notifyListeners();
    if (_on && _key != null) _crossfadeTo(_key!, const Duration(milliseconds: 1500));
  }

  /// Quieter for a moment so "Play do" can be heard over the pad.
  void duck() {
    if (!_on) return;
    final p = _players[_active];
    final gen = _gen;
    p.setVolume(_volume * 0.3);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (gen == _gen && _on) p.setVolume(_volume);
    });
  }

  Future<void> _crossfadeTo(int semitone, Duration time) async {
    final gen = ++_gen;
    final light = switch (_voicing) {
      PadVoicing.light => true,
      PadVoicing.full => false,
      PadVoicing.auto => await AudioOutput.isPhoneSpeaker(),
    };
    if (gen != _gen) return;
    if (light != _usingLight) {
      _usingLight = light;
      notifyListeners();
    }
    final old = _players[_active];
    final next = _players[1 - _active];
    try {
      await next.stop(); // may still be fading out from an interrupted glide
      await next.setVolume(0);
      await next.setAsset(assetFor(semitone, light: light));
      await next.setLoopMode(LoopMode.one);
    } catch (e) {
      debugPrint('Pad could not load: $e');
      return;
    }
    if (gen != _gen) return;
    unawaited(next.play()); // play() completes only when playback ends
    _active = 1 - _active;
    final oldFrom = old.playing ? old.volume : 0.0;
    await _ramp(gen, time, (x) {
      next.setVolume(_volume * math.sin(x * math.pi / 2)); // equal-power crossfade
      if (oldFrom > 0) old.setVolume(oldFrom * math.cos(x * math.pi / 2));
    });
    if (gen == _gen) await old.stop();
  }

  Future<void> _ramp(int gen, Duration time, void Function(double x) apply) async {
    const step = 40;
    final n = math.max(1, time.inMilliseconds ~/ step);
    for (var i = 1; i <= n; i++) {
      if (gen != _gen) return;
      apply(i / n);
      await Future<void>.delayed(const Duration(milliseconds: step));
    }
  }
}
