import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import '../../../core/emoji/emoji_catalog_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/inline_feedback.dart';

class ZunoEmojiPicker extends ConsumerStatefulWidget {
  final ValueChanged<String> onSelected;
  final VoidCallback? onBackspace;
  final EmojiSearchLayout searchLayout;
  final ValueNotifier<bool>? searching;

  const ZunoEmojiPicker({
    required this.onSelected,
    this.onBackspace,
    this.searchLayout = EmojiSearchLayout.grid,
    this.searching,
    super.key,
  });

  @override
  ConsumerState<ZunoEmojiPicker> createState() => _ZunoEmojiPickerState();
}

class _ZunoEmojiPickerState extends ConsumerState<ZunoEmojiPicker> {
  var _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && !_shown) _retryProvisional();
    _shown = shown;
  }

  void _retryProvisional() {
    if (!(ref.read(emojiCatalogProvider).value?.provisional ?? false)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(emojiCatalogProvider);
    });
  }

  @override
  Widget build(BuildContext context) =>
      switch (ref.watch(emojiCatalogProvider)) {
        AsyncData(value: final catalog) => EmojiPicker(
          catalog: catalog,
          labels: _labels(context.l10n),
          onSelected: widget.onSelected,
          onBackspace: widget.onBackspace,
          searchLayout: widget.searchLayout,
          searching: widget.searching,
          searchFieldBuilder: _searchField,
        ),
        AsyncError() => const SizedBox.shrink(),
        _ => const Center(child: InlineSpinner()),
      };
}

EmojiLabels _labels(AppLocalizations l10n) => EmojiLabels(
  categories: {
    EmojiCategory.smileysPeople: l10n.chatEmojiSmileysPeople,
    EmojiCategory.animalsNature: l10n.chatEmojiAnimalsNature,
    EmojiCategory.foodDrink: l10n.chatEmojiFoodDrink,
    EmojiCategory.travelPlaces: l10n.chatEmojiTravelPlaces,
    EmojiCategory.activities: l10n.chatEmojiActivities,
    EmojiCategory.objects: l10n.chatEmojiObjects,
    EmojiCategory.symbols: l10n.chatEmojiSymbols,
    EmojiCategory.flags: l10n.chatEmojiFlags,
  },
  recent: l10n.chatEmojiRecent,
  search: l10n.chatEmojiSearch,
  noResults: l10n.chatEmojiNoResults,
  noRecents: l10n.chatEmojiNoRecents,
  backspace: l10n.commonDelete,
  closeSearch: l10n.chatEmojiBackToAll,
);

Widget _searchField(
  BuildContext context,
  TextEditingController controller,
  FocusNode focusNode,
  String hint,
) => ZunoTextField(
  autofillHints: null,
  controller: controller,
  focusNode: focusNode,
  textInputAction: TextInputAction.search,
  decoration: InputDecoration(
    hintText: hint,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  ),
);
