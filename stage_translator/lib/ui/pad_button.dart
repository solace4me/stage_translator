// lib/ui/pad_button.dart
//
// The Pad button on every song. Tap: pad on/off (fades in and out).
// Hold: volume and sound (Auto / Full / Light). It also tells the pad which
// key this song is in, so a running pad glides into it.

import 'package:flutter/material.dart';

import '../services/pad_player.dart';

class PadButton extends StatefulWidget {
  /// Doh of the key you are playing in (0 = C ... 11 = B).
  final int semitone;
  const PadButton({super.key, required this.semitone});

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  final _pad = PadEngine.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pad.follow(widget.semitone));
  }

  @override
  void didUpdateWidget(PadButton old) {
    super.didUpdateWidget(old);
    if (old.semitone != widget.semitone) _pad.follow(widget.semitone);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pad,
      builder: (context, _) {
        final on = _pad.isPlaying;
        final scheme = Theme.of(context).colorScheme;
        return Tooltip(
          message: on ? 'Stop pad (hold for settings)' : 'Play pad (hold for settings)',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _pad.toggle(widget.semitone),
            onLongPress: () => showPadSettings(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: on ? Colors.cyanAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? Colors.cyanAccent : scheme.outline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.graphic_eq, size: 20, color: on ? Colors.black : null),
                const SizedBox(width: 4),
                Text('Pad',
                    style: TextStyle(fontWeight: FontWeight.bold, color: on ? Colors.black : null)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showPadSettings(BuildContext context) {
  final pad = PadEngine.instance;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => ListenableBuilder(
      listenable: pad,
      builder: (c, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pad', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'A soft sound in the song\'s key. It keeps playing between songs and glides into the next key.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.volume_down),
              Expanded(child: Slider(value: pad.volume, onChanged: pad.setVolume)),
              const Icon(Icons.volume_up),
            ]),
            const SizedBox(height: 8),
            const Text('Sound for'),
            const SizedBox(height: 8),
            SegmentedButton<PadVoicing>(
              segments: const [
                ButtonSegment(value: PadVoicing.auto, label: Text('Auto')),
                ButtonSegment(value: PadVoicing.full, label: Text('Speaker')),
                ButtonSegment(value: PadVoicing.light, label: Text('Phone')),
              ],
              selected: {pad.voicing},
              onSelectionChanged: (s) => pad.setVoicing(s.first),
            ),
            const SizedBox(height: 8),
            Text(
              pad.voicing == PadVoicing.auto
                  ? 'Auto: deep version through a cable or Bluetooth, lighter version on the phone speaker'
                      '${pad.isPlaying ? ' (now: ${pad.usingLight ? 'phone' : 'mixer / speaker'}).' : '.'}'
                  : pad.voicing == PadVoicing.full
                      ? 'Deep version with low notes, for a mixer, a big speaker or headphones.'
                      : 'Lighter version that still sounds full on the phone\'s own speaker.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            if (pad.isPlaying) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    pad.stop();
                    Navigator.pop(c);
                  },
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop pad'),
                ),
              ),
            ],
          ]),
        ),
      ),
    ),
  );
}
