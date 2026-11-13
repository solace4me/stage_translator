// lib/ui/feedback_dialog.dart
//
// "Send feedback": stars, a comment box and an optional name. The app adds
// its version, the phone's Android version and which screen you were on.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/feedback_service.dart';

/// [where] says which screen it came from, e.g. "Hymn: It Is Well".
Future<void> showFeedbackDialog(BuildContext context, {required String where}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<SendResult>(
    context: context,
    builder: (_) => _FeedbackDialog(where: where),
  );
  final text = switch (result) {
    SendResult.sent => 'Thank you! Your feedback was sent.',
    SendResult.savedForLater =>
      "Saved, but not sent yet: ${lastFeedbackError ?? 'no connection'}. It will be sent next time you open the app.",
    _ => null,
  };
  if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
}

class _FeedbackDialog extends StatefulWidget {
  final String where;
  const _FeedbackDialog({required this.where});

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _message = TextEditingController();
  final _name = TextEditingController();
  int? _rating;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    FeedbackService.savedName().then((n) {
      if (mounted && _name.text.isEmpty) _name.text = n;
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final item = FeedbackItem(
      message: _message.text.trim(),
      rating: _rating,
      name: _name.text.trim(),
      details: await FeedbackService.details(widget.where),
      createdAt: DateTime.now(),
    );
    await FeedbackService.saveName(item.name);
    final result = await FeedbackService.send(item);
    if (result == SendResult.notConfigured) {
      // No form yet: hand it to Telegram / WhatsApp / email instead.
      await Share.share(item.asText(), subject: 'Stage Translator Pro feedback');
    }
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send feedback'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How is the app working for you?'),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '$i of 5',
                  onPressed: _sending ? null : () => setState(() => _rating = i),
                  icon: Icon(
                    (_rating ?? 0) >= i ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'What worked, what went wrong, what you wish it did…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('Your app version, Android version and this screen are added to help fix problems.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending || _message.text.trim().isEmpty ? null : _send,
          child: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send'),
        ),
      ],
    );
  }
}
