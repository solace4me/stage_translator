// lib/services/pdf_exporter.dart
//
// Builds a clean A4 PDF of a translated sheet in DejaVu Sans Mono (monospace,
// so the chords stay above their words, and it has the ♭ sign that the
// built-in PDF Courier lacks), with chord lines in bold, then shares it.

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/solfege_engine.dart';
import '../data/sheet.dart';

class PdfExporter {
  /// Writes the PDF to the temporary folder and returns the file.
  static Future<File> build(Sheet sheet) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSansMono.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSansMono-Bold.ttf'));
    final doc = pw.Document(title: sheet.title, creator: 'Stage Translator Pro');

    final lines = sheet.translatedText.split('\n');
    // Pick a size so the longest line fits the page width (0.602 em a character).
    const pageWidth = 595.0 - 2 * 40; // A4 minus margins, in points
    final longest = lines.fold<int>(1, (m, l) => l.length > m ? l.length : m);
    final fontSize = (pageWidth / (longest * 0.602)).clamp(7.0, 12.0);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(sheet.title, style: pw.TextStyle(font: bold, fontSize: 16)),
              pw.Text(
                '${sheet.notation == LabelNotation.numbers ? '1' : 'Doh'} = ${sheet.performanceKey}'
                '${sheet.sheetKey != sheet.performanceKey ? '  (written in ${sheet.sheetKey})' : ''}',
                style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          for (final line in lines)
            pw.Text(
              // Non-breaking spaces stop the PDF layout from collapsing runs
              // of spaces, which would break chord alignment.
              line.isEmpty ? ' ' : line.replaceAll(' ', ' '),
              style: pw.TextStyle(
                font: SolfegeEngine.isChordLine(SolfegeEngine.stripLabels(line)) ? bold : regular,
                fontSize: fontSize,
                lineSpacing: 1.5,
              ),
            ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final safeName = sheet.title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    final file = File('${dir.path}/${safeName.isEmpty ? 'sheet' : safeName} - '
        '${sheet.notation == LabelNotation.numbers ? '1' : 'Doh'} ${sheet.performanceKey}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  /// Opens the native share sheet (Mail, WhatsApp, Save to Files, Drive...).
  static Future<void> share(Sheet sheet) async {
    final file = await build(sheet);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: '${sheet.title} (Doh = ${sheet.performanceKey})',
    );
  }
}
