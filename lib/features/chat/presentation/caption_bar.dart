import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/keep_clear.dart';
import 'emoji_panel.dart';
import 'send_icon.dart';

class CaptionBar extends StatelessWidget {
  final TextEditingController controller;
  final EmojiPanelController emojiPanel;
  final String? sendTooltip;
  final VoidCallback onSend;

  const CaptionBar({
    required this.controller,
    required this.emojiPanel,
    required this.onSend,
    this.sendTooltip,
    super.key,
  });

  @override
  Widget build(BuildContext context) => KeepClearArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: emojiPanel,
              builder: (context, _) => ZunoTextField(
                autofillHints: null,
                controller: controller,
                focusNode: emojiPanel.focus,
                onTap: emojiPanel.fieldTapped,
                readOnly: emojiPanel.typingPaused,
                showCursor: true,
                decoration: InputDecoration(
                  hintText: context.l10n.chatCaptionHint,
                  suffixIcon: EmojiToggleButton(controller: emojiPanel),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const SendIcon(),
            tooltip: sendTooltip ?? context.l10n.commonSend,
            onPressed: onSend,
          ),
        ],
      ),
    ),
  );
}
