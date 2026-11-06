import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../emoji_catalog.dart';
import '../emoji_entry.dart';
import '../emoji_labels.dart';
import 'emoji_cell.dart';

const _minHeaderHeight = 32.0;
const _headerPadding = 12.0;
const _textPadding = 16.0;
const _barHeight = 48.0;

const _icons = {
  EmojiCategory.smileysPeople: Icons.emoji_emotions_outlined,
  EmojiCategory.animalsNature: Icons.emoji_nature_outlined,
  EmojiCategory.foodDrink: Icons.emoji_food_beverage_outlined,
  EmojiCategory.travelPlaces: Icons.emoji_transportation_outlined,
  EmojiCategory.activities: Icons.emoji_events_outlined,
  EmojiCategory.objects: Icons.emoji_objects_outlined,
  EmojiCategory.symbols: Icons.emoji_symbols_outlined,
  EmojiCategory.flags: Icons.emoji_flags_outlined,
};

class EmojiBrowser extends StatefulWidget {
  final EmojiCatalog catalog;
  final EmojiLabels labels;
  final List<String> recent;
  final ValueChanged<String> onPick;
  final EmojiLongPress onLongPress;
  final VoidCallback onSearch;
  final VoidCallback? onBackspace;

  const EmojiBrowser({
    super.key,
    required this.catalog,
    required this.labels,
    required this.recent,
    required this.onPick,
    required this.onLongPress,
    required this.onSearch,
    this.onBackspace,
  });

  @override
  State<EmojiBrowser> createState() => _EmojiBrowserState();
}

class _Section {
  final String title;
  final IconData icon;
  final List<String> emoji;
  final List<EmojiEntry?> entries;

  const _Section(this.title, this.icon, this.emoji, this.entries);
}

class _Layout {
  final int columns;
  final double extent;
  final List<double> headers;
  final double emptyHeight;
  final List<double> offsets;

  const _Layout(
    this.columns,
    this.extent,
    this.headers,
    this.emptyHeight,
    this.offsets,
  );
}

class _EmojiBrowserState extends State<EmojiBrowser> {
  final _scroll = ScrollController();
  final _selected = ValueNotifier(0);
  late List<_Section> _sections;
  _Layout? _layout;
  Object? _layoutKey;

  @override
  void initState() {
    super.initState();
    _sections = _buildSections();
    _scroll.addListener(_followScroll);
  }

  @override
  void didUpdateWidget(EmojiBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sections = _buildSections();
    _layoutKey = null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _selected.dispose();
    super.dispose();
  }

  List<_Section> _buildSections() {
    final catalog = widget.catalog;
    return [
      _Section(widget.labels.recent, Icons.schedule_outlined, widget.recent, [
        for (final e in widget.recent) catalog.entryOf(e),
      ]),
      for (final category in EmojiCategory.values)
        if (catalog.category(category) case final entries
            when entries.isNotEmpty)
          _Section(widget.labels.categories[category]!, _icons[category]!, [
            for (final e in entries) catalog.shown(e),
          ], entries),
    ];
  }

  void _followScroll() {
    final offsets = _layout?.offsets;
    if (offsets == null) return;
    final offset = _scroll.offset + 1;
    var index = 0;
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] <= offset) index = i;
    }
    _selected.value = index;
  }

  void _jump(int index) {
    final offsets = _layout?.offsets;
    if (offsets == null) return;
    _scroll.jumpTo(math.min(offsets[index], _scroll.position.maxScrollExtent));
    _selected.value = index;
  }

  _Layout _layoutFor(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final headerStyle = _headerStyle(context);
    final bodyStyle = DefaultTextStyle.of(context).style;
    final key = (width, scaler, headerStyle, bodyStyle);
    final cached = _layout;
    if (cached != null && key == _layoutKey) return cached;
    final columns = math.max(1, (width / emojiCellExtent).floor());
    final extent = width / columns;
    final textWidth = width - 2 * _headerPadding;
    final headers = [
      for (final section in _sections)
        math.max(
          _minHeaderHeight,
          _textHeight(section.title, headerStyle, scaler, textWidth) +
              _headerPadding,
        ),
    ];
    final emptyHeight = math.max(
      extent,
      _textHeight(widget.labels.noRecents, bodyStyle, scaler, textWidth) +
          _textPadding,
    );
    final offsets = <double>[];
    var offset = 0.0;
    for (final (i, section) in _sections.indexed) {
      offsets.add(offset);
      offset +=
          headers[i] +
          (section.emoji.isEmpty
              ? emptyHeight
              : (section.emoji.length / columns).ceil() * extent);
    }
    _layoutKey = key;
    return _layout = _Layout(columns, extent, headers, emptyHeight, offsets);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _bar(context),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = _layoutFor(context, constraints.maxWidth);
            final headerStyle = _headerStyle(context);
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                for (final (i, section) in _sections.indexed) ...[
                  SliverToBoxAdapter(
                    child: _header(
                      section.title,
                      headerStyle,
                      layout.headers[i],
                    ),
                  ),
                  if (section.emoji.isEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: layout.emptyHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _headerPadding,
                          ),
                          child: Center(
                            child: Text(
                              widget.labels.noRecents,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: layout.columns,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => CatalogEmojiCell(
                          catalog: widget.catalog,
                          emoji: section.emoji[i],
                          entry: section.entries[i],
                          onPick: widget.onPick,
                          onLongPress: widget.onLongPress,
                        ),
                        childCount: section.emoji.length,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );

  double _textHeight(
    String text,
    TextStyle style,
    TextScaler scaler,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: math.max(0, width));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  TextStyle _headerStyle(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTextStyle.of(context).style
        .merge(theme.textTheme.labelMedium)
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
  }

  Widget _header(String title, TextStyle style, double height) => SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: _headerPadding),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(title, style: style),
      ),
    ),
  );

  Widget _bar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final backspace = widget.onBackspace;
    return SizedBox(
      height: _barHeight,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: widget.labels.search,
            color: colors.onSurfaceVariant,
            onPressed: widget.onSearch,
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _selected,
              builder: (context, selected, _) => ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (i, section) in _sections.indexed)
                    IconButton(
                      icon: Icon(section.icon),
                      tooltip: section.title,
                      isSelected: i == selected,
                      color: i == selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      onPressed: () => _jump(i),
                    ),
                ],
              ),
            ),
          ),
          if (backspace != null)
            IconButton(
              icon: const Icon(Icons.backspace_outlined),
              tooltip: widget.labels.backspace,
              color: colors.onSurfaceVariant,
              onPressed: backspace,
            ),
        ],
      ),
    );
  }
}
