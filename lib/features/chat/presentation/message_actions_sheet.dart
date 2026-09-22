import 'package:flutter/material.dart';

enum MessageAction { reply, edit, delete, share, save, copy, report }

const _quickEmoji = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

Future<MessageAction?> showMessageActionsSheet(
  BuildContext context, {
  required bool canPost,
  required bool canEdit,
  required bool canDelete,
  required bool isOwn,
  required bool isTextMessage,
  required bool isAttachment,
  required int galleryCount,
  required List<Widget> facts,
  required void Function(String key) onReact,
  required VoidCallback onMoreReactions,
}) {
  final isGallery = galleryCount > 1;
  return showModalBottomSheet<MessageAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;

      Widget action(MessageAction value, IconData icon, String label) {
        final color = value == MessageAction.delete ? colors.error : null;
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            label,
            style: color == null ? null : TextStyle(color: color),
          ),
          visualDensity: const VisualDensity(vertical: -2),
          onTap: () => Navigator.of(context).pop(value),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canPost)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final emoji in _quickEmoji)
                        _ReactionButton(
                          onTap: () {
                            Navigator.of(context).pop();
                            onReact(emoji);
                          },
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22, height: 1.1),
                          ),
                        ),
                      _ReactionButton(
                        tooltip: 'More reactions',
                        onTap: () {
                          Navigator.of(context).pop();
                          onMoreReactions();
                        },
                        child: Icon(Icons.add, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              if (canPost)
                action(MessageAction.reply, Icons.reply_outlined, 'Reply'),
              if (isTextMessage)
                action(MessageAction.copy, Icons.copy_outlined, 'Copy'),
              if (canEdit)
                action(MessageAction.edit, Icons.edit_outlined, 'Edit'),
              if (isAttachment) ...[
                action(
                  MessageAction.share,
                  Icons.share_outlined,
                  isGallery ? 'Share all ($galleryCount)' : 'Share',
                ),
                action(
                  MessageAction.save,
                  Icons.download_outlined,
                  isGallery ? 'Save all ($galleryCount)' : 'Save',
                ),
              ],
              if (canDelete)
                action(MessageAction.delete, Icons.delete_outline, 'Delete'),
              if (!isOwn)
                action(MessageAction.report, Icons.flag_outlined, 'Report'),
              if (facts.isNotEmpty) ...[
                Divider(height: 9, color: colors.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: facts,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class MessageFact extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const MessageFact({super.key, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  const _ReactionButton({
    required this.child,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Center(child: child)),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
