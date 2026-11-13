// lib/services/release_guard.dart
//
// Lets a test build stop after a date, and lets you force everyone onto a
// newer version from a small file online. Both are set when you build:
//
//   flutter build apk --release \
//     --dart-define=EXPIRES=2026-11-20 \
//     --dart-define=UPDATE_URL=https://<you>.github.io/stage-translator/version.json \
//     --dart-define=DOWNLOAD_URL=https://t.me/<your channel>
//
// EXPIRES: last day the build works (it stops the next morning). Leave it out
//   for the stable version.
// UPDATE_URL: a JSON file like
//   {"minBuild": 2, "message": "Please install the new version.",
//    "downloadUrl": "https://t.me/..."}
//   Any build whose number (the +N in pubspec's version) is below minBuild
//   shows the update screen. Change the file any time; no new APK needed.
// DOWNLOAD_URL: where the "Get the latest version" button goes if the file
//   does not say.
//
// Offline the app keeps working until the expiry date. Turning the phone's
// clock back does not help: the app remembers the latest date it has seen,
// and checks the real date online whenever it can.

import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

enum GuardState { ok, expired, updateRequired }

class GuardResult {
  final GuardState state;
  final String message;
  final String? downloadUrl;

  const GuardResult(this.state, {this.message = '', this.downloadUrl});

  static const ok = GuardResult(GuardState.ok);
  bool get blocked => state != GuardState.ok;
}

/// What the online file says.
class RemoteConfig {
  final int? minBuild;
  final String? message;
  final String? downloadUrl;

  const RemoteConfig({this.minBuild, this.message, this.downloadUrl});

  static RemoteConfig? tryParse(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return RemoteConfig(
        minBuild: (j['minBuild'] as num?)?.toInt(),
        message: j['message'] as String?,
        downloadUrl: j['downloadUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class ReleaseGuard {
  static const expires = String.fromEnvironment('EXPIRES');
  static const updateUrl = String.fromEnvironment('UPDATE_URL');
  static const downloadUrl = String.fromEnvironment('DOWNLOAD_URL');

  /// True for test builds (an expiry date was given).
  static bool get isTestBuild => expires.isNotEmpty;

  /// The decision, with no phone or network involved (unit-tested).
  static GuardResult evaluate({
    required DateTime now,
    required String expires,
    required int build,
    RemoteConfig? remote,
    String fallbackDownloadUrl = '',
  }) {
    final url = (remote?.downloadUrl?.isNotEmpty ?? false)
        ? remote!.downloadUrl
        : (fallbackDownloadUrl.isEmpty ? null : fallbackDownloadUrl);
    if (remote?.minBuild != null && build < remote!.minBuild!) {
      return GuardResult(GuardState.updateRequired,
          message: remote.message ?? 'A newer version of Stage Translator Pro is available. '
              'Please install it to keep using the app.',
          downloadUrl: url);
    }
    final end = expiryEnd(expires);
    if (end != null && !now.isBefore(end)) {
      return GuardResult(GuardState.expired,
          message: remote?.message ??
              'Thank you for testing Stage Translator Pro! This test version has ended. '
                  'Please install the latest version.',
          downloadUrl: url);
    }
    return GuardResult.ok;
  }

  /// Midnight after the expiry day, or null if there is no (valid) date.
  static DateTime? expiryEnd(String expires) {
    final d = DateTime.tryParse(expires);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day + 1);
  }

  // ------------------------------------------------------- on the phone

  /// Quick check with no network: expiry date against the trusted clock.
  static Future<GuardResult> checkOffline() async {
    if (!isTestBuild) return GuardResult.ok;
    final now = await _trustedNow(null);
    return evaluate(now: now, expires: expires, build: await _build(), fallbackDownloadUrl: downloadUrl);
  }

  /// Full check: also reads the online file and the real date (a few seconds
  /// at most; offline it falls back to [checkOffline]).
  static Future<GuardResult> checkOnline() async {
    RemoteConfig? remote;
    DateTime? serverTime;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(updateUrl.isNotEmpty ? updateUrl : 'https://www.google.com/generate_204');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 6));
      final date = res.headers.value(HttpHeaders.dateHeader);
      if (date != null) {
        try {
          serverTime = HttpDate.parse(date).toLocal();
        } catch (_) {}
      }
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 6));
      if (updateUrl.isNotEmpty && res.statusCode == 200) remote = RemoteConfig.tryParse(body);
    } catch (_) {
      // offline or blocked: decide from what we know
    } finally {
      client.close(force: true);
    }
    if (!isTestBuild && remote == null) return GuardResult.ok;
    final now = await _trustedNow(serverTime);
    return evaluate(
      now: now,
      expires: expires,
      build: await _build(),
      remote: remote,
      fallbackDownloadUrl: downloadUrl,
    );
  }

  static Future<int> _build() async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The latest of: the phone clock, the real date from the internet, and
  /// the latest date this app has seen before. Saved for next time.
  static Future<DateTime> _trustedNow(DateTime? server) async {
    var now = DateTime.now();
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}/.clock');
      if (await file.exists()) {
        final seen = int.tryParse((await file.readAsString()).trim());
        if (seen != null) {
          final last = DateTime.fromMillisecondsSinceEpoch(seen);
          if (last.isAfter(now)) now = last;
        }
      }
    } catch (_) {}
    if (server != null && server.isAfter(now)) now = server;
    try {
      await file?.writeAsString('${now.millisecondsSinceEpoch}', flush: true);
    } catch (_) {}
    return now;
  }
}
