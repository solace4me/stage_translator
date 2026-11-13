// lib/ui/pedal.dart
//
// Bluetooth page-turner pedals (AirTurn, PageFlip, Donner, cheap "BT page
// turners") pair as a keyboard and send a key per press. We listen for the
// keys they use and turn them into forward / back:
//   forward: Page Down, Down, Right, Space, Media Next
//   back:    Page Up, Up, Left, Media Previous
// Each screen decides what forward means: scroll a page, then the next verse,
// then the next song in the set.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PedalAction { forward, back }

final _keys = <LogicalKeyboardKey, PedalAction>{
  LogicalKeyboardKey.pageDown: PedalAction.forward,
  LogicalKeyboardKey.arrowDown: PedalAction.forward,
  LogicalKeyboardKey.arrowRight: PedalAction.forward,
  LogicalKeyboardKey.space: PedalAction.forward,
  LogicalKeyboardKey.mediaTrackNext: PedalAction.forward,
  LogicalKeyboardKey.pageUp: PedalAction.back,
  LogicalKeyboardKey.arrowUp: PedalAction.back,
  LogicalKeyboardKey.arrowLeft: PedalAction.back,
  LogicalKeyboardKey.mediaTrackPrevious: PedalAction.back,
};

/// Calls [onPedal] for pedal presses while this screen is the one on top.
/// [enabled] can switch it off, e.g. while you are typing in the editor.
class Pedal extends StatefulWidget {
  final ValueChanged<PedalAction> onPedal;
  final bool Function()? enabled;
  final Widget child;

  const Pedal({super.key, required this.onPedal, this.enabled, required this.child});

  @override
  State<Pedal> createState() => _PedalState();
}

class _PedalState extends State<Pedal> {
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _handle(KeyEvent event) {
    if (!mounted) return false;
    final action = _keys[event.logicalKey];
    if (action == null) return false;
    if (_route != null && !_route!.isCurrent) return false; // a dialog or another screen is on top
    if (widget.enabled != null && !widget.enabled!()) return false;
    if (event is KeyDownEvent) widget.onPedal(action); // ignore key repeat and key up
    return true; // keep the key away from text fields and lists
  }

  @override
  Widget build(BuildContext context) {
    _route = ModalRoute.of(context);
    return widget.child;
  }
}

/// Scrolls about three quarters of a screen. Returns false when already at
/// the end in that direction (so the caller can move to the next verse/song).
bool pageScroll(ScrollController controller, PedalAction action) {
  if (!controller.hasClients) return false;
  final p = controller.position;
  const edge = 2.0;
  final step = p.viewportDimension * 0.75;
  final double target;
  if (action == PedalAction.forward) {
    if (p.pixels >= p.maxScrollExtent - edge) return false;
    target = math.min(p.pixels + step, p.maxScrollExtent);
  } else {
    if (p.pixels <= p.minScrollExtent + edge) return false;
    target = math.max(p.pixels - step, p.minScrollExtent);
  }
  controller.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  return true;
}
