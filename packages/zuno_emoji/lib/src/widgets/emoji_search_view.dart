import 'package:flutter/material.dart';

import '../emoji_catalog.dart';
import '../emoji_entry.dart';
import '../emoji_labels.dart';
import 'emoji_cell.dart';

enum EmojiSearchLayout { grid, row }

typedef EmojiSearchFieldBuilder = Widget Function(
  BuildContext context,
  TextEditingController controller,
  FocusNode focusNode,
  String hint,
);

class EmojiSearchView extends StatefulWidget {
  final EmojiCatalog catalog;
  final EmojiLabels labels;
  final EmojiSearchLayout layout;
  final EmojiSearchFieldBuilder fieldBuilder;
  final ValueChanged<String> onPick;
  final EmojiLongPress onLongPress;
  final VoidCallback onClose;

  const EmojiSearchView({
    super.key,
    required this.catalog,
    required this.labels,
    required this.layout,
    required this.fieldBuilder,
    required this.onPick,
    required this.onLongPress,
    required this.onClose,
  });

  @override
  State<EmojiSearchView> createState() => _EmojiSearchViewState();
}

class _EmojiSearchViewState extends State<EmojiSearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  var _query = '';
  late var _results = _recent();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_search);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<(String?, EmojiEntry?)> _recent() => [
    for (final emoji in widget.catalog.recent)
      (emoji, widget.catalog.entryOf(emoji)),
  ];

  void _search() {
    final query = _controller.text;
    if (query == _query) return;
    setState(() {
      _query = query;
      _results = query.trim().isEmpty
          ? _recent()
          : [for (final entry in widget.catalog.search(query)) (null, entry)];
    });
  }

  bool get _nothingFound => _results.isEmpty && _query.trim().isNotEmpty;

  Widget _cell(BuildContext context, int index) {
    final (emoji, entry) = _results[index];
    return CatalogEmojiCell(
      catalog: widget.catalog,
      emoji: emoji ?? widget.catalog.shown(entry!),
      entry: entry,
      onPick: widget.onPick,
      onLongPress: widget.onLongPress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = Row(
      children: [
        IconButton(
          icon: const BackButtonIcon(),
          tooltip: widget.labels.closeSearch,
          onPressed: widget.onClose,
        ),
        Expanded(
          child: widget.fieldBuilder(
            context,
            _controller,
            _focus,
            widget.labels.search,
          ),
        ),
      ],
    );
    final empty = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(widget.labels.noResults),
      ),
    );
    return switch (widget.layout) {
      EmojiSearchLayout.row => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: emojiCellExtent,
            child: _nothingFound
                ? empty
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemExtent: emojiCellExtent,
                    itemCount: _results.length,
                    itemBuilder: _cell,
                  ),
          ),
          field,
        ],
      ),
      EmojiSearchLayout.grid => Column(
        children: [
          field,
          Expanded(
            child: _nothingFound
                ? empty
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: emojiCellExtent,
                        ),
                    itemCount: _results.length,
                    itemBuilder: _cell,
                  ),
          ),
        ],
      ),
    };
  }
}
