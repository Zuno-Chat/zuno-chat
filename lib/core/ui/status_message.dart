import 'package:flutter/material.dart';

import '../l10n/display_text.dart';

class StatusMessage extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? body;
  final Widget? action;

  const StatusMessage({
    required IconData this.icon,
    @displayText required this.title,
    @displayText this.body,
    this.action,
    super.key,
  });

  const StatusMessage.busy({
    @displayText required this.title,
    @displayText this.body,
    this.action,
    super.key,
  }) : icon = null;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final body = this.body;
    final action = this.action;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon == null)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 32), action],
          ],
        ),
      ),
    );
  }
}
