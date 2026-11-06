import 'dart:async';

import 'package:flutter/material.dart';

import '../emoji_catalog.dart';
import '../emoji_entry.dart';
import '../emoji_labels.dart';
import 'emoji_browser.dart';
import 'emoji_search_view.dart';
import 'tone_picker.dart';

export 'emoji_search_view.dart' show EmojiSearchFieldBuilder, EmojiSearchLayout;

class EmojiPicker extends StatefulWidget {
  final EmojiCatalog catalog;
  final EmojiLabels labels;
  final ValueChanged<String> onSelected;
  final EmojiSearchFieldBuilder searchFieldBuilder;
  final VoidCallback? onBackspace;
  final EmojiSearchLayout searchLayout;
  final ValueNotifier<bool>? searching;

  const EmojiPicker({
    super.key,
    required this.catalog,
    required this.labels,
    required this.onSelected,
    required this.searchFieldBuilder,
    this.onBackspace,
    this.searchLayout = EmojiSearchLayout.grid,
    this.searching,
  });

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  final _browserKey = GlobalKey();
  late var _recent = widget.catalog.recent;
  var _shown = false;
  var _browserHeight = 0.0;
  ValueNotifier<bool>? _ownSearching;

  ValueNotifier<bool> get _searching =>
      widget.searching ?? (_ownSearching ??= ValueNotifier(false));

  @override
  void initState() {
    super.initState();
    _searching.addListener(_searchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && !_shown) _recent = widget.catalog.recent;
    _shown = shown;
  }

  @override
  void didUpdateWidget(EmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.searching, widget.searching)) return;
    (oldWidget.searching ?? _ownSearching)?.removeListener(_searchChanged);
    _searching.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _searching.removeListener(_searchChanged);
    _ownSearching?.dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (_searching.value) {
      _browserHeight = _browserKey.currentContext?.size?.height ?? 0;
    }
    setState(() {});
  }

  void _pick(String emoji) {
    widget.onSelected(emoji);
    unawaited(widget.catalog.recents.add(emoji));
  }

  Future<void> _pickTone(BuildContext cellContext, EmojiEntry entry) async {
    final picked = await showTonePicker(
      cellContext,
      entry: entry,
      label: widget.catalog.label,
    );
    if (picked == null || !mounted) return;
    _pick(picked);
    setState(() {});
  }

  void _setSearching(bool searching) => _searching.value = searching;

  @override
  Widget build(BuildContext context) {
    final browser = EmojiBrowser(
      key: _browserKey,
      catalog: widget.catalog,
      labels: widget.labels,
      recent: _recent,
      onPick: _pick,
      onLongPress: _pickTone,
      onSearch: () => _setSearching(true),
      onBackspace: widget.onBackspace,
    );
    return Material(
      type: MaterialType.transparency,
      child: _searching.value
          ? Stack(
              children: [
                Offstage(
                  child: TickerMode(
                    enabled: false,
                    child: SizedBox(height: _browserHeight, child: browser),
                  ),
                ),
                EmojiSearchView(
                  catalog: widget.catalog,
                  labels: widget.labels,
                  layout: widget.searchLayout,
                  fieldBuilder: widget.searchFieldBuilder,
                  onPick: _pick,
                  onLongPress: _pickTone,
                  onClose: () => _setSearching(false),
                ),
              ],
            )
          : browser,
    );
  }
}
