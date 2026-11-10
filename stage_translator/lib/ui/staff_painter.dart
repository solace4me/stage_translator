// lib/ui/staff_painter.dart
//
// Draws a StaffLayoutResult: one clean staff per row, the active voice's
// notes in cyan, the solfège above, and every verse's lyrics below with the
// current verse bright and the others dimmed. Draws key signatures on every
// row, key changes inside a row, the time signature, beams, ties and slurs.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../score/staff_layout.dart';

class StaffMetrics {
  /// Distance between two staff lines.
  final double lineGap;
  final double solfaFontSize;
  final double lyricFontSize;
  final int verseCount;

  const StaffMetrics({
    this.lineGap = 11,
    this.solfaFontSize = 15,
    this.lyricFontSize = 14,
    this.verseCount = 1,
  });

  double get stepHeight => lineGap / 2;
  double get solfaBand => solfaFontSize + 14;
  double get aboveStaff => lineGap * 3.5; // room for ledger lines and stems
  double get staffHeight => lineGap * 4;
  double get belowStaff => lineGap * 3.5;
  double get lyricLine => lyricFontSize * 1.5;
  double get stemLength => lineGap * 3.3;

  double get rowHeight =>
      solfaBand + aboveStaff + staffHeight + belowStaff + verseCount * lyricLine + 18;

  /// y of the bottom staff line within a row.
  double get bottomLine => solfaBand + aboveStaff + staffHeight;
}

class StaffPainter extends CustomPainter {
  final StaffLayoutResult layout;
  final StaffMetrics m;
  final List<int> verses;
  final int currentVerse;
  final Color ink;
  final Color accent;
  final Color dim;

  StaffPainter({
    required this.layout,
    required this.m,
    required this.verses,
    required this.currentVerse,
    required this.ink,
    required this.accent,
    required this.dim,
  });

  static const _mono = 'DejaVuSansMono';

  @override
  void paint(Canvas canvas, Size size) {
    for (var r = 0; r < layout.rows.length; r++) {
      canvas.save();
      canvas.translate(0, r * m.rowHeight);
      _paintRow(canvas, layout.rows[r]);
      canvas.restore();
    }
  }

  double _y(num step) => m.bottomLine - step * m.stepHeight;
  double get _headW => m.lineGap * 1.35;

  Paint get _linePaint => Paint()
    ..color = ink.withValues(alpha: 0.55)
    ..strokeWidth = 1;

  void _paintRow(Canvas canvas, StaffRow row) {
    final line = _linePaint;
    final staffInk = ink.withValues(alpha: 0.8);

    // Staff lines.
    for (var s = 0; s <= 8; s += 2) {
      canvas.drawLine(Offset(8, _y(s)), Offset(row.endX, _y(s)), line);
    }

    // Header: clef, key signature, time signature (first row).
    _text(canvas, layout.clef == Clef.treble ? 'G' : 'F', Offset(20, _y(4)),
        size: m.lineGap * 2, color: staffInk, bold: true, center: true);
    var x = 40.0;
    x = _keySignature(canvas, x, row.startFifths, row.startKeySteps, const []);
    final time = layout.time;
    if (row.showTime && time != null) {
      _text(canvas, '${time.beats}', Offset(x + 8, _y(6)),
          size: m.lineGap * 1.9, color: staffInk, bold: true, center: true);
      _text(canvas, '${time.beatType}', Offset(x + 8, _y(2)),
          size: m.lineGap * 1.9, color: staffInk, bold: true, center: true);
    }

    // Bar lines.
    for (final b in row.barlines) {
      canvas.drawLine(Offset(b, _y(8)), Offset(b, _y(0)), line);
    }

    // Key changes inside the row: a double bar, then naturals and the new key.
    for (final k in row.keyChanges) {
      canvas.drawLine(Offset(k.x - 6, _y(8)), Offset(k.x - 6, _y(0)), line);
      canvas.drawLine(Offset(k.x - 3, _y(8)), Offset(k.x - 3, _y(0)), line);
      _keySignature(canvas, k.x + 6, k.fifths, k.steps, k.cancelSteps);
    }

    // Beamed notes draw their stems with the beam, not one by one.
    final beamed = <int>{for (final b in row.beams) ...b.glyphs};
    for (var i = 0; i < row.glyphs.length; i++) {
      _paintGlyph(canvas, row.glyphs[i], drawStem: !beamed.contains(i));
    }
    for (final b in row.beams) {
      _paintBeam(canvas, row, b);
    }
    for (final a in row.arcs) {
      _paintArc(canvas, a);
    }
    for (final e in row.extenders) {
      _paintExtender(canvas, row, e);
    }
  }

  /// The hold line under a syllable sung over several notes.
  void _paintExtender(Canvas canvas, StaffRow row, LyricExtender e) {
    final i = verses.indexOf(e.verse);
    if (i < 0) return;
    final current = e.verse == currentVerse;
    final baseline = m.bottomLine + m.belowStaff + i * m.lyricLine + m.lyricLine / 2 + m.lyricFontSize * 0.45;
    var x1 = e.x1;
    if (e.fromWord) {
      // Start just after the printed word.
      final g = row.glyphs.firstWhere((g) => (g.x - e.x1).abs() < 0.5, orElse: () => row.glyphs.first);
      final text = g.note.lyric(e.verse)?.displayText ?? '';
      x1 += _textWidth(text, m.lyricFontSize, bold: current) / 2 + 3;
    }
    final x2 = e.x2 + _headW / 2;
    if (x2 <= x1) return;
    canvas.drawLine(
      Offset(x1, baseline),
      Offset(x2, baseline),
      Paint()
        ..color = current ? ink : dim
        ..strokeWidth = 1.2,
    );
  }

  double _textWidth(String s, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  /// Draws naturals for [cancel] then the signature; returns the x after it.
  double _keySignature(Canvas canvas, double x, int fifths, List<int> steps, List<int> cancel) {
    final color = ink.withValues(alpha: 0.8);
    for (final s in cancel) {
      _text(canvas, '♮', Offset(x, _y(s)), size: m.lineGap * 1.5, color: color, center: true);
      x += 11;
    }
    final sign = fifths > 0 ? '#' : '♭';
    for (final s in steps) {
      _text(canvas, sign, Offset(x, _y(s)), size: m.lineGap * 1.5, color: color, center: true);
      x += 11;
    }
    return x;
  }

  double _stemX(StaffGlyph g, bool up) => up ? g.x + _headW / 2 - 1 : g.x - _headW / 2 + 1;

  void _paintGlyph(Canvas canvas, StaffGlyph g, {required bool drawStem}) {
    final n = g.note;
    final held = n.isTieContinuation;
    final color = held ? accent.withValues(alpha: 0.55) : accent;

    // Solfège above the staff (not repeated on a held note).
    if (n.syllable != null && !held) {
      _text(canvas, n.syllable!, Offset(g.x, m.solfaBand / 2),
          size: m.solfaFontSize, color: accent, bold: true, center: true, font: _mono);
    }

    if (g.step == null) {
      _paintRest(canvas, g);
    } else {
      final step = g.step!;
      final y = _y(step);
      final headH = m.lineGap * 0.95;
      for (final s in g.ledgerSteps) {
        canvas.drawLine(Offset(g.x - _headW, _y(s)), Offset(g.x + _headW, _y(s)), _linePaint);
      }
      final hollow = g.value == NoteValue.whole || g.value == NoteValue.half;
      final head = Paint()
        ..color = color
        ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 2;
      canvas.save();
      canvas.translate(g.x, y);
      canvas.rotate(-0.35);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: _headW, height: headH), head);
      canvas.restore();

      if (drawStem && g.value != NoteValue.whole) {
        final stem = Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;
        final sx = _stemX(g, g.stemUp);
        final ey = g.stemUp ? y - m.stemLength : y + m.stemLength;
        canvas.drawLine(Offset(sx, y), Offset(sx, ey), stem);
        final flags = g.value == NoteValue.eighth ? 1 : (g.value == NoteValue.sixteenth ? 2 : 0);
        for (var f = 0; f < flags; f++) {
          final fy = ey + (g.stemUp ? f * 7.0 : -f * 7.0);
          final path = Path()
            ..moveTo(sx, fy)
            ..quadraticBezierTo(sx + 10, fy + (g.stemUp ? 8 : -8), sx + 8, fy + (g.stemUp ? 18 : -18));
          canvas.drawPath(path, stem);
        }
      }
      if (g.dotted) {
        final dotStep = step.isEven ? step + 1 : step; // dots sit in a space
        canvas.drawCircle(Offset(g.x + _headW, _y(dotStep)), 2.2, Paint()..color = color);
      }
      if (g.accidental != null) {
        _text(canvas, g.accidental!, Offset(g.x - _headW - 6, y),
            size: m.lineGap * 1.6, color: color, center: true);
      }
    }

    // Lyrics: every verse, the current one bright.
    final lyricTop = m.bottomLine + m.belowStaff;
    for (var i = 0; i < verses.length; i++) {
      final l = n.lyric(verses[i]);
      if (l == null) continue;
      final current = verses[i] == currentVerse;
      _text(canvas, l.displayText, Offset(g.x, lyricTop + i * m.lyricLine + m.lyricLine / 2),
          size: m.lyricFontSize, color: current ? ink : dim, bold: current, center: true);
    }
  }

  /// Stems end on one straight beam line from the first note to the last,
  /// sloped with the melody (at most 1.5 staff spaces) and moved away from
  /// the heads until every stem is at least 2.5 spaces long.
  void _paintBeam(Canvas canvas, StaffRow row, BeamGroup b) {
    final gs = [for (final i in b.glyphs) row.glyphs[i]];
    final up = b.stemUp;
    final xs = [for (final g in gs) _stemX(g, up)];
    final heads = [for (final g in gs) _y(g.step!)];
    final dir = up ? -1.0 : 1.0;

    var y1 = heads.first + dir * m.stemLength;
    var y2 = heads.last + dir * m.stemLength;
    final maxSlope = m.lineGap * 1.5;
    if ((y2 - y1).abs() > maxSlope) y2 = y1 + maxSlope * (y2 > y1 ? 1 : -1);
    double beamY(double x) => xs.first == xs.last ? y1 : y1 + (y2 - y1) * (x - xs.first) / (xs.last - xs.first);

    // Shift the whole beam so no stem is shorter than the minimum.
    final minStem = m.lineGap * 2.5;
    var shift = 0.0;
    for (var i = 0; i < gs.length; i++) {
      final len = (beamY(xs[i]) - heads[i]) * dir;
      if (len < minStem) shift = math.max(shift, minStem - len);
    }
    y1 += dir * shift;
    y2 += dir * shift;

    final color = accent;
    final stem = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    for (var i = 0; i < gs.length; i++) {
      canvas.drawLine(Offset(xs[i], heads[i]), Offset(xs[i], beamY(xs[i])), stem);
    }

    final thick = m.lineGap * 0.45;
    void beamSegment(double xa, double xb, int level) {
      final off = -dir * level * (thick + 3); // second beam sits inside the first
      final path = Path()
        ..moveTo(xa, beamY(xa) + off)
        ..lineTo(xb, beamY(xb) + off)
        ..lineTo(xb, beamY(xb) + off - dir * thick)
        ..lineTo(xa, beamY(xa) + off - dir * thick)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    beamSegment(xs.first, xs.last, 0);
    // Second beam: across neighbouring sixteenths, or a short stub.
    for (var i = 0; i < gs.length; i++) {
      if (b.levels[i] < 2) continue;
      final next = i + 1 < gs.length && b.levels[i + 1] >= 2;
      final prev = i > 0 && b.levels[i - 1] >= 2;
      if (next) {
        beamSegment(xs[i], xs[i + 1], 1);
      } else if (!prev) {
        final stub = m.lineGap * 0.9;
        i == gs.length - 1 ? beamSegment(xs[i] - stub, xs[i], 1) : beamSegment(xs[i], xs[i] + stub, 1);
      }
    }
  }

  void _paintArc(Canvas canvas, ArcSpan a) {
    final dir = a.above ? -1.0 : 1.0;
    final gap = m.lineGap * 0.9; // start just off the note heads
    final y1 = _y(a.step1) + dir * gap;
    final y2 = _y(a.step2) + dir * gap;
    final x1 = a.x1 + 4, x2 = a.x2 - 4;
    if (x2 <= x1) return;
    final lift = math.min(m.lineGap * (a.isTie ? 0.9 : 1.6), (x2 - x1) * 0.25 + 4);
    final midY = (y1 + y2) / 2 + dir * lift;
    // A thin crescent: two curves, filled, like engraved ties and slurs.
    final path = Path()
      ..moveTo(x1, y1)
      ..quadraticBezierTo((x1 + x2) / 2, midY, x2, y2)
      ..quadraticBezierTo((x1 + x2) / 2, midY - dir * 1.8, x1, y1)
      ..close();
    canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.85));
  }

  void _paintRest(Canvas canvas, StaffGlyph g) {
    final p = Paint()..color = accent.withValues(alpha: 0.8);
    switch (g.value) {
      case NoteValue.whole:
        canvas.drawRect(Rect.fromLTWH(g.x - 7, _y(6), 14, m.stepHeight), p);
      case NoteValue.half:
        canvas.drawRect(Rect.fromLTWH(g.x - 7, _y(4) - m.stepHeight, 14, m.stepHeight), p);
      default:
        final path = Path()
          ..moveTo(g.x - 3, _y(7))
          ..lineTo(g.x + 4, _y(5.5))
          ..lineTo(g.x - 3, _y(4))
          ..lineTo(g.x + 4, _y(2));
        canvas.drawPath(
            path,
            p
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4);
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {required double size, required Color color, bool bold = false, bool center = false, String? font}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: font,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(StaffPainter old) =>
      old.layout != layout || old.currentVerse != currentVerse || old.verses != verses;
}
