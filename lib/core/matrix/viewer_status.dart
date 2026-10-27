import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

const viewerProgress = CircularProgressIndicator(color: Colors.white);

class ViewerNotice extends StatelessWidget {
  final String text;
  final VoidCallback? retry;

  const ViewerNotice({required this.text, this.retry, super.key});

  @override
  Widget build(BuildContext context) {
    final retry = this.retry;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          if (retry != null)
            TextButton(
              onPressed: retry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(context.l10n.commonRetry),
            ),
        ],
      ),
    );
  }
}
