import 'package:flutter/material.dart';

import '../emoji_entry.dart';
import 'emoji_cell.dart';

Future<String?> showTonePicker(
  BuildContext cellContext, {
  required EmojiEntry entry,
  required String Function(String emoji) label,
}) {
  final box = cellContext.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(cellContext).overlay!.context.findRenderObject()!
          as RenderBox;
  final cell = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return showMenu<String>(
    context: cellContext,
    position: RelativeRect.fromRect(cell, Offset.zero & overlay.size),
    constraints: const BoxConstraints(
      maxWidth: (skinToneCount + 1) * emojiCellExtent + 16,
    ),
    items: [_ToneGrid(entry: entry, label: label)],
  );
}

class _ToneGrid extends PopupMenuEntry<String> {
  final EmojiEntry entry;
  final String Function(String emoji) label;

  const _ToneGrid({required this.entry, required this.label});

  int get _rows => entry.tones == ToneKind.two ? skinToneCount + 1 : 1;

  @override
  double get height => _rows * emojiCellExtent;

  @override
  bool represents(String? value) => false;

  @override
  State<_ToneGrid> createState() => _ToneGridState();
}

class _ToneGridState extends State<_ToneGrid> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    Widget cell(String emoji) => SizedBox.square(
      dimension: emojiCellExtent,
      child: EmojiCell(
        emoji: emoji,
        label: widget.label(emoji),
        onTap: () => Navigator.of(context).pop(emoji),
      ),
    );
    if (entry.tones == ToneKind.one) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [cell(entry.emoji), ...entry.variants.map(cell)],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(entry.emoji),
        for (var row = 0; row < skinToneCount; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var column = 0; column < skinToneCount; column++)
                cell(entry.variants[EmojiEntry.pairIndex(row, column)]),
            ],
          ),
      ],
    );
  }
}
