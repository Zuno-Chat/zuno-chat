import 'package:flutter/material.dart';

import '../emoji_catalog.dart';
import '../emoji_entry.dart';

const emojiCellExtent = 48.0;
const _emojiSize = 28.0;

typedef EmojiLongPress = void Function(
  BuildContext cellContext,
  EmojiEntry entry,
);

class EmojiCell extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const EmojiCell({
    super.key,
    required this.emoji,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: emojiCellExtent / 2,
      child: ExcludeSemantics(
        child: Center(
          child: Text(
            emoji,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(fontSize: _emojiSize, height: 1.2),
          ),
        ),
      ),
    ),
  );
}

class CatalogEmojiCell extends StatelessWidget {
  final EmojiCatalog catalog;
  final String emoji;
  final EmojiEntry? entry;
  final ValueChanged<String> onPick;
  final EmojiLongPress onLongPress;

  const CatalogEmojiCell({
    super.key,
    required this.catalog,
    required this.emoji,
    required this.entry,
    required this.onPick,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    return EmojiCell(
      emoji: emoji,
      label: catalog.label(emoji),
      onTap: () => onPick(emoji),
      onLongPress: entry == null || !catalog.showsTones(entry)
          ? null
          : () => onLongPress(context, entry),
    );
  }
}
