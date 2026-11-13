// lib/services/feedback_service.dart
//
// Sends tester feedback to the Google Form in FeedbackConfig. If the phone is
// offline the comment is kept and sent the next time the app opens.

import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/feedback_config.dart';

class FeedbackItem {
  final String message;
  final int? rating; // 1..5
  final String name;
  final String details;
  final DateTime createdAt;

  const FeedbackItem({
    required this.message,
    this.rating,
    this.name = '',
    this.details = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'message': message,
        'rating': rating,
        'name': name,
        'details': details,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FeedbackItem.fromJson(Map<String, dynamic> j) => FeedbackItem(
        message: j['message'] as String? ?? '',
        rating: (j['rating'] as num?)?.toInt(),
        name: j['name'] as String? ?? '',
        details: j['details'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  /// The form fields to post (empty entry ids are left out).
  Map<String, String> formFields() => {
        if (FeedbackConfig.messageEntry.isNotEmpty) FeedbackConfig.messageEntry: message,
        if (FeedbackConfig.ratingEntry.isNotEmpty && rating != null) FeedbackConfig.ratingEntry: '$rating',
        if (FeedbackConfig.nameEntry.isNotEmpty && name.isNotEmpty) FeedbackConfig.nameEntry: name,
        if (FeedbackConfig.detailsEntry.isNotEmpty) FeedbackConfig.detailsEntry: details,
      };

  /// Plain text for the share sheet (when no form is set up).
  String asText() => [
        'Stage Translator Pro feedback',
        if (rating != null) 'Rating: $rating/5',
        if (name.isNotEmpty) 'From: $name',
        '',
        message,
        '',
        details,
      ].join('\n');
}

enum SendResult { sent, savedForLater, notConfigured }

/// Why the last send failed (shown to the tester, helps find the cause).
String? lastFeedbackError;

class FeedbackService {
  /// "Build 3 · Android 14 · Screen: Hymn: It Is Well · 2026-11-13 08:15"
  static Future<String> details(String where) async {
    var build = '?';
    var version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      build = info.buildNumber;
      version = info.version;
    } catch (_) {}
    final now = DateTime.now();
    final stamp = '${now.year}-${_two(now.month)}-${_two(now.day)} ${_two(now.hour)}:${_two(now.minute)}';
    return 'Version $version (build $build) · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
        ' · Screen: $where · $stamp';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static Future<SendResult> send(FeedbackItem item) async {
    if (!FeedbackConfig.isSet) return SendResult.notConfigured;
    final error = await _post(item);
    lastFeedbackError = error;
    if (error == null) {
      flush(); // also send anything left over from before
      return SendResult.sent;
    }
    await _queue(item);
    return SendResult.savedForLater;
  }

  /// Sends feedback saved while offline. Call at app start.
  static Future<void> flush() async {
    if (!FeedbackConfig.isSet) return;
    final file = await _outbox();
    if (!await file.exists()) return;
    List<FeedbackItem> items;
    try {
      items = [
        for (final j in jsonDecode(await file.readAsString()) as List)
          FeedbackItem.fromJson((j as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return;
    }
    final left = <FeedbackItem>[];
    for (final i in items) {
      if (await _post(i) != null) left.add(i);
    }
    await _write(file, left);
  }

  /// Null when Google accepted it, else a short reason.
  static Future<String?> _post(FeedbackItem item) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Mozilla/5.0 (Linux; Android) StageTranslatorPro';
    try {
      // Sent with an exact length (not "chunked"), which Google's servers expect.
      final body = utf8.encode(Uri(queryParameters: item.formFields()).query);
      final req = await client.postUrl(Uri.parse(FeedbackConfig.submitUrl));
      req.followRedirects = false;
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      if (res.statusCode >= 200 && res.statusCode < 400) return null;
      return switch (res.statusCode) {
        400 => 'Google rejected it (400): check the entry ids in feedback_config.dart',
        401 || 403 => 'The form needs sign-in (${res.statusCode}): turn off sign-in in the form settings',
        404 => 'Form not found (404): check formId in feedback_config.dart',
        _ => 'Google answered ${res.statusCode}',
      };
    } on SocketException catch (e) {
      return 'No connection (${e.osError?.message ?? e.message})';
    } on HandshakeException catch (e) {
      return 'Secure connection failed (${e.message})';
    } catch (e) {
      return '$e';
    } finally {
      client.close(force: true);
    }
  }

  static Future<File> _outbox() async =>
      File('${(await getApplicationSupportDirectory()).path}/feedback_outbox.json');

  static Future<void> _queue(FeedbackItem item) async {
    final file = await _outbox();
    var items = <Map<String, dynamic>>[];
    try {
      if (await file.exists()) {
        items = (jsonDecode(await file.readAsString()) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    items.add(item.toJson());
    await file.writeAsString(jsonEncode(items), flush: true);
  }

  static Future<void> _write(File file, List<FeedbackItem> items) async {
    if (items.isEmpty) {
      if (await file.exists()) await file.writeAsString('[]', flush: true);
      return;
    }
    await file.writeAsString(jsonEncode([for (final i in items) i.toJson()]), flush: true);
  }

  // The tester's name, so they type it once.
  static Future<String> savedName() async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/feedback_name');
      return await f.exists() ? (await f.readAsString()).trim() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveName(String name) async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/feedback_name');
      await f.writeAsString(name.trim(), flush: true);
    } catch (_) {}
  }
}
