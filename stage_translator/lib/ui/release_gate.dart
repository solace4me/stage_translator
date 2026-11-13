// lib/ui/release_gate.dart
//
// Wraps the app. Shows the app straight away, checks in the background (at
// start and whenever the app comes back to the front), and covers it with the
// "test version has ended" / "please update" screen when needed. Saved songs
// are never touched, so they are all there after updating.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/release_guard.dart';

class ReleaseGate extends StatefulWidget {
  final Widget child;
  const ReleaseGate({super.key, required this.child});

  @override
  State<ReleaseGate> createState() => _ReleaseGateState();
}

class _ReleaseGateState extends State<ReleaseGate> with WidgetsBindingObserver {
  GuardResult _result = GuardResult.ok;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final offline = await ReleaseGuard.checkOffline();
      if (mounted && offline.blocked) setState(() => _result = offline);
      final online = await ReleaseGuard.checkOnline();
      if (mounted) setState(() => _result = online);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_result.blocked) return widget.child;
    return _BlockedScreen(result: _result, onRetry: _check);
  }
}

class _BlockedScreen extends StatelessWidget {
  final GuardResult result;
  final VoidCallback onRetry;
  const _BlockedScreen({required this.result, required this.onRetry});

  Future<void> _download(BuildContext context) async {
    final url = result.downloadUrl;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ended = result.state == GuardState.expired;
    return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(ended ? Icons.hourglass_bottom : Icons.system_update, size: 72, color: Colors.cyanAccent),
                const SizedBox(height: 24),
                Text(ended ? 'This test version has ended' : 'Update required',
                    textAlign: TextAlign.center, style: text.headlineSmall),
                const SizedBox(height: 16),
                Text(result.message, textAlign: TextAlign.center, style: text.bodyLarge),
                const SizedBox(height: 12),
                Text('Your saved songs and set lists stay on this phone and will be there after you update.',
                    textAlign: TextAlign.center, style: text.bodySmall),
                const SizedBox(height: 32),
                if (result.downloadUrl != null)
                  FilledButton.icon(
                    onPressed: () => _download(context),
                    icon: const Icon(Icons.download),
                    label: const Text('Get the latest version'),
                  ),
                const SizedBox(height: 8),
                TextButton(onPressed: onRetry, child: const Text('Check again')),
              ],
            ),
          ),
        ),
    );
  }
}
