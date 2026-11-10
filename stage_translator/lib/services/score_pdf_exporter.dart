// lib/services/score_pdf_exporter.dart
//
// PDF export for hymns, two kinds:
//  * Sol-fa: all voices in Curwen notation, as real text (small, sharp,
//    searchable), in the bundled DejaVu Sans Mono so columns line up.
//  * Staff: the single-voice staff view, drawn by the same StaffPainter the
//    screen uses, rendered to images page by page (black on white).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../score/curwen.dart';
import '../score/staff_layout.dart';
import '../ui/staff_painter.dart';

class ScorePdfExporter {
  ScorePdfExporter._();

  static const _margin = 36.0;

  static Future<pw.Font> _font(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));

  /// All voices in tonic sol-fa.
  static Future<File> solfa(CurwenScore c, {required String title, int verse = 1}) async {
    final regular = await _font('DejaVuSansMono');
    final bold = await _font('DejaVuSansMono-Bold');
    const fontSize = 9.5;
    final pageWidth = PdfPageFormat.a4.width - 2 * _margin;
    final maxChars = (pageWidth / (fontSize * 0.602)).floor();

    final doc = pw.Document(title: title, creator: 'Stage Translator Pro');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margin),
      header: (context) => _header(title, '${c.keyLabel}${c.timeLabel == null ? '' : '   ${c.timeLabel}'}'
          '${verse > 1 ? '   Verse $verse' : ''}', bold, regular),
      footer: (context) => _footer(context, regular),
      build: (context) => [
        for (final system in c.systems(maxChars))
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final line in system.lines)
                  pw.Text(
                    line.text.replaceAll(' ', ' '), // keep runs of spaces
                    style: pw.TextStyle(
                      font: line.kind == CurwenLineKind.words ? regular : bold,
                      fontSize: fontSize,
                      color: line.kind == CurwenLineKind.keyChange
                          ? PdfColors.orange800
                          : (line.kind == CurwenLineKind.words ? PdfColors.grey800 : PdfColors.black),
                      lineSpacing: 2,
                    ),
                  ),
              ],
            ),
          ),
      ],
    ));
    return _write(doc, '$title - sol-fa');
  }

  /// The staff view of one voice, rendered page by page.
  static Future<File> staff(
    StaffLayoutResult layout, {
    required String title,
    required String subtitle,
    required List<int> verses,
    required int currentVerse,
    required double width,
  }) async {
    final regular = await _font('DejaVuSansMono');
    final bold = await _font('DejaVuSansMono-Bold');
    final metrics = StaffMetrics(verseCount: verses.isEmpty ? 0 : verses.length);

    // Fit as many rows as the page holds at the page's width.
    final pageWidth = PdfPageFormat.a4.width - 2 * _margin;
    final pageHeight = PdfPageFormat.a4.height - 2 * _margin - 60; // header + footer
    final scale = pageWidth / width;
    final rowsPerPage = (pageHeight / (metrics.rowHeight * scale)).floor().clamp(1, 50);

    final images = <pw.MemoryImage>[];
    for (var start = 0; start < layout.rows.length; start += rowsPerPage) {
      final rows = layout.rows.sublist(start, (start + rowsPerPage).clamp(0, layout.rows.length));
      images.add(await _renderRows(
        StaffLayoutResult(layout.clef, start == 0 ? layout.time : null, rows),
        metrics,
        verses,
        currentVerse,
        width,
      ));
    }

    final doc = pw.Document(title: title, creator: 'Stage Translator Pro');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margin),
      header: (context) => _header(title, subtitle, bold, regular),
      footer: (context) => _footer(context, regular),
      build: (context) => [for (final img in images) pw.Image(img, width: pageWidth)],
    ));
    return _write(doc, '$title - staff');
  }

  static Future<pw.MemoryImage> _renderRows(
    StaffLayoutResult layout,
    StaffMetrics metrics,
    List<int> verses,
    int currentVerse,
    double width,
  ) async {
    const pixelRatio = 2.5; // sharp enough to print
    final height = layout.rows.length * metrics.rowHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
    StaffPainter(
      layout: layout,
      m: metrics,
      verses: verses,
      currentVerse: currentVerse,
      ink: Colors.black,
      accent: const Color(0xFF0B3D91), // dark blue reads well on paper
      dim: Colors.black45,
    ).paint(canvas, Size(width, height));
    final image = await recorder.endRecording().toImage((width * pixelRatio).ceil(), (height * pixelRatio).ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return pw.MemoryImage(bytes!.buffer.asUint8List());
  }

  static pw.Widget _header(String title, String subtitle, pw.Font bold, pw.Font regular) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 15)),
            pw.Text(subtitle, style: pw.TextStyle(font: regular, fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context context, pw.Font regular) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey600)),
      );

  static Future<File> _write(pw.Document doc, String name) async {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    final file = File('${dir.path}/${safe.isEmpty ? 'hymn' : safe}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  /// Opens the phone's share sheet (WhatsApp, email, Save to Files ...).
  static Future<void> share(File file, String title) => Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: title,
      );
}
