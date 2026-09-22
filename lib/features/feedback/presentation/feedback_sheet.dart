import 'package:flutter/material.dart';

import '../../../core/errors/feedback.dart';

typedef SendFeedback = Future<void> Function(String message);

Future<void> showFeedbackSheet(
  BuildContext context, {
  SendFeedback onSend = sendFeedback,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FeedbackSheet(onSend: onSend),
  );
  if (sent ?? false) {
    messenger.showSnackBar(const SnackBar(content: Text('Feedback sent.')));
  }
}

class _FeedbackSheet extends StatefulWidget {
  final SendFeedback onSend;

  const _FeedbackSheet({required this.onSend});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _message = TextEditingController();
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.onSend(_message.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = !_sending && _message.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text('Send feedback', style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Your feedback goes to a reporting service with your app '
                  'version and Android build. Names and addresses are '
                  'removed. Nothing identifies you, so there is no reply.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: TextField(
                  autofillHints: null,
                  controller: _message,
                  enabled: !_sending,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Your feedback',
                    alignLabelWithHint: true,
                    errorText: _failed
                        ? 'Feedback not sent. Check your connection and try '
                              'again.'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: FilledButton(
                  onPressed: canSend ? _send : null,
                  child: const Text('Send feedback'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
