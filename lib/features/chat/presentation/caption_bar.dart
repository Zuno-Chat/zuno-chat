import 'package:flutter/material.dart';

import '../../../core/ui/keep_clear.dart';
import 'send_icon.dart';

class CaptionBar extends StatelessWidget {
  final TextEditingController controller;
  final String sendTooltip;
  final VoidCallback onSend;

  const CaptionBar({
    required this.controller,
    required this.onSend,
    this.sendTooltip = 'Send',
    super.key,
  });

  @override
  Widget build(BuildContext context) => KeepClearArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              autofillHints: null,
              controller: controller,
              decoration: const InputDecoration(hintText: 'Add a caption…'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const SendIcon(),
            tooltip: sendTooltip,
            onPressed: onSend,
          ),
        ],
      ),
    ),
  );
}
