import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class FailureNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const FailureNotice({required this.message, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonTryAgain),
            ),
        ],
      ),
    );
  }
}
