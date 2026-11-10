// lib/ui/hymn_import_guide.dart
//
// Plain-language help for the Hymns tab: what a hymn file is, how to turn
// a PDF or photo into one for free (MuseScore), and where to find hymns
// that are already done. Links can be copied (no browser plugin needed).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HymnImportGuide extends StatelessWidget {
  /// Opened because the user picked a PDF or picture.
  final bool cameFromPicture;

  /// Scroll straight to "Where to find hymn files".
  final bool startOnFind;

  const HymnImportGuide({super.key, this.cameFromPicture = false, this.startOnFind = false});

  @override
  Widget build(BuildContext context) {
    final findKey = GlobalKey();
    if (startOnFind) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = findKey.currentContext;
        if (c != null) Scrollable.ensureVisible(c);
      });
    }
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Adding a hymn')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          if (cameFromPicture)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'That was a PDF or a picture. The app can\'t read printed notes from a '
                  'picture yet, but you can turn it into a hymn file for free. Here\'s how.',
                ),
              ),
            ),
          Text('What the app needs', style: t.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'A hymn file (called MusicXML, ending in .mxl or .musicxml). Unlike a PDF or '
            'photo, it holds the real notes, so the app can write every voice in sol-fa, '
            'in any key, with no mistakes from guessing.',
          ),
          const SizedBox(height: 24),
          Text('Turn a PDF into a hymn file (free)', style: t.titleLarge),
          const SizedBox(height: 4),
          const Text('You need a computer for this part, once per hymn.'),
          const SizedBox(height: 8),
          const _Step(1, 'Install MuseScore Studio (free) on your computer.', link: 'https://musescore.org/download'),
          const _Step(2,
              'In MuseScore choose File › Import PDF. It opens a page where you sign in (free account) '
              'and upload the PDF. Clean, printed pages work best; blurry photos often fail.'),
          const _Step(3, 'Open the result in MuseScore and check the notes. Fix any wrong ones.'),
          const _Step(4, 'Choose File › Export, pick MusicXML, and save the .mxl file.'),
          const _Step(5,
              'Send the .mxl file to your phone (WhatsApp, email or USB), then in the app tap '
              '+ Hymn › Open a hymn file.'),
          const SizedBox(height: 8),
          const Text(
            'Only have a photo? Scan the page flat and bright (most phone camera apps have '
            '"Scan document"), save it as PDF, then follow the steps above.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 24),
          Text('Where to find hymn files', key: findKey, style: t.titleLarge),
          const SizedBox(height: 4),
          const Text('Most traditional hymns are old enough to be free to download.'),
          const SizedBox(height: 8),
          const _Source(
            'MuseScore.com',
            'Search the hymn name, then Download › MusicXML. A free account can download '
                'public-domain music (up to 20 a day).',
            'https://musescore.com',
          ),
          const _Source(
            'Choral Public Domain Library (CPDL)',
            'Tens of thousands of free choral scores. Many have a MusicXML or MuseScore file '
                'next to the PDF.',
            'https://www.cpdl.org',
          ),
          const _Source(
            'OpenScore',
            'Free, checked scores of public-domain music, downloadable as MusicXML.',
            'https://openscore.cc',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  final String? link;
  const _Step(this.n, this.text, {this.link});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 13, child: Text('$n', style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text),
                  if (link != null) _CopyLink(link!),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Source extends StatelessWidget {
  final String name, text, link;
  const _Source(this.name, this.text, this.link);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(text),
              _CopyLink(link),
            ],
          ),
        ),
      );
}

/// Shows a link with a copy button, so it can be pasted into a browser.
class _CopyLink extends StatelessWidget {
  final String url;
  const _CopyLink(this.url);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: SelectableText(url, style: const TextStyle(color: Colors.cyanAccent)),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied. Paste it into your browser.')),
              );
            },
          ),
        ],
      );
}
