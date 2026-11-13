import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/services/release_guard.dart';

void main() {
  final day = DateTime(2026, 11, 20, 18); // evening of the last day

  test('works through the whole expiry day, stops the next morning', () {
    expect(ReleaseGuard.evaluate(now: day, expires: '2026-11-20', build: 1).blocked, isFalse);
    final next = ReleaseGuard.evaluate(
        now: DateTime(2026, 11, 21, 0, 1), expires: '2026-11-20', build: 1, fallbackDownloadUrl: 'https://t.me/x');
    expect(next.state, GuardState.expired);
    expect(next.downloadUrl, 'https://t.me/x');
  });

  test('no expiry date means it never expires', () {
    expect(ReleaseGuard.evaluate(now: DateTime(2099), expires: '', build: 1).blocked, isFalse);
  });

  test('online file can force an update, even before the expiry date', () {
    final remote = RemoteConfig.tryParse('{"minBuild": 3, "message": "New version!", "downloadUrl": "https://a.b"}');
    final r = ReleaseGuard.evaluate(now: day, expires: '2026-12-31', build: 2, remote: remote);
    expect(r.state, GuardState.updateRequired);
    expect(r.message, 'New version!');
    expect(r.downloadUrl, 'https://a.b');
    expect(ReleaseGuard.evaluate(now: day, expires: '', build: 3, remote: remote).blocked, isFalse);
  });

  test('a broken online file is ignored', () {
    expect(RemoteConfig.tryParse('<html>oops</html>'), isNull);
  });
}
