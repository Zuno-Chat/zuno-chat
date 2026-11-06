import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import '../../../core/emoji/emoji_catalog_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/navigation/chat_route.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/ui/close_own_route.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/keyboard.dart';
import '../../../core/ui/route_settled.dart';
import 'zuno_emoji_picker.dart';

enum _Mode { hidden, emoji, search, closingSearch, toKeyboard }

const _portraitHeightKey = 'chat.keyboard_height.portrait';
const _landscapeHeightKey = 'chat.keyboard_height.landscape';
const _defaultPortraitHeight = 300.0;
const _defaultLandscapeShare = 0.45;
const _maxShare = 0.6;
const _minKeyboard = 100.0;
const _settle = Duration(milliseconds: 300);
const _keyboardWait = Duration(seconds: 1);

String _heightKey(Size view) =>
    view.width > view.height ? _landscapeHeightKey : _portraitHeightKey;

class EmojiPanelController extends ChangeNotifier {
  final TextEditingController Function() _text;
  final SharedPreferences _preferences;
  final focus = FocusNode();
  final searching = ValueNotifier(false);
  var _mode = _Mode.hidden;
  var _inset = 0.0;
  var _view = Size.zero;
  Timer? _settleTimer;
  Timer? _waitTimer;

  EmojiPanelController({required this._text, required this._preferences}) {
    searching.addListener(_searchChanged);
  }

  bool get open => switch (_mode) {
    _Mode.emoji || _Mode.search || _Mode.closingSearch => true,
    _Mode.hidden || _Mode.toKeyboard => false,
  };

  bool get typingPaused => _mode == _Mode.emoji || _mode == _Mode.closingSearch;

  double _heightFor(Size view) {
    final stored = _preferences.getDouble(_heightKey(view));
    final fallback = view.width > view.height
        ? view.height * _defaultLandscapeShare
        : _defaultPortraitHeight;
    return math.min(stored ?? fallback, view.height * _maxShare);
  }

  void showEmoji() {
    _set(_Mode.emoji);
    _focusFieldAfterFrame();
  }

  void showKeyboard() {
    _set(_Mode.toKeyboard);
    _waitForKeyboard();
    if (!focus.hasFocus) focus.requestFocus();
  }

  void close() {
    _set(_Mode.hidden);
    closeKeyboard();
  }

  void _searchChanged() {
    if (searching.value) {
      _set(_Mode.search);
    } else if (_mode == _Mode.search) {
      _set(_Mode.emoji);
      _focusFieldAfterFrame();
    }
  }

  void fieldTapped() {
    if (open) showKeyboard();
  }

  void keyboardInset(double inset, Size view) {
    final falling = inset < _inset - 1;
    _inset = inset;
    _view = view;
    if (falling) {
      _settleTimer?.cancel();
      if (_mode == _Mode.toKeyboard) _set(_Mode.hidden);
      if (_mode == _Mode.search && inset < _minKeyboard) {
        _set(_Mode.closingSearch);
        _focusFieldAfterFrame();
      }
      if (_mode == _Mode.closingSearch && inset < 1) _set(_Mode.emoji);
      return;
    }
    if (inset < _minKeyboard) return;
    _waitTimer?.cancel();
    if (_mode == _Mode.hidden || _mode == _Mode.toKeyboard) _settleLater();
  }

  void insert(String emoji) {
    final controller = _text();
    final value = controller.value;
    final selection = _selectionOf(value);
    controller.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, emoji),
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
  }

  void backspace() {
    final controller = _text();
    final value = controller.value;
    final selection = _selectionOf(value);
    if (!selection.isCollapsed) {
      controller.value = TextEditingValue(
        text: value.text.replaceRange(selection.start, selection.end, ''),
        selection: TextSelection.collapsed(offset: selection.start),
      );
      return;
    }
    if (selection.start == 0) return;
    final before = value.text
        .substring(0, selection.start)
        .characters
        .skipLast(1)
        .toString();
    controller.value = TextEditingValue(
      text: before + value.text.substring(selection.start),
      selection: TextSelection.collapsed(offset: before.length),
    );
  }

  TextSelection _selectionOf(TextEditingValue value) {
    final length = value.text.length;
    final selection = value.selection;
    if (!selection.isValid) return TextSelection.collapsed(offset: length);
    return TextSelection(
      baseOffset: math.min(selection.start, length),
      extentOffset: math.min(selection.end, length),
    );
  }

  void _focusFieldAfterFrame() {
    if (focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (typingPaused && focus.canRequestFocus) focus.requestFocus();
    });
  }

  void _waitForKeyboard() {
    _waitTimer?.cancel();
    if (_inset >= _minKeyboard) {
      _settleLater();
      return;
    }
    _waitTimer = Timer(_keyboardWait, () {
      if (_mode == _Mode.toKeyboard && _inset < _minKeyboard) {
        _set(_Mode.hidden);
      }
    });
  }

  void _settleLater() {
    _settleTimer?.cancel();
    _settleTimer = Timer(_settle, _settled);
  }

  void _settled() {
    if (_inset >= _minKeyboard &&
        (_mode == _Mode.hidden || _mode == _Mode.toKeyboard)) {
      final key = _heightKey(_view);
      if (_preferences.getDouble(key) != _inset) {
        unawaited(_preferences.setDouble(key, _inset));
      }
    }
    if (_mode == _Mode.toKeyboard) _set(_Mode.hidden);
  }

  void _set(_Mode mode) {
    if (mode == _mode) return;
    _mode = mode;
    if (mode != _Mode.search) searching.value = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _waitTimer?.cancel();
    searching.dispose();
    focus.dispose();
    super.dispose();
  }
}

class EmojiPanel extends ConsumerStatefulWidget {
  final EmojiPanelController controller;

  const EmojiPanel({required this.controller, super.key});

  @override
  ConsumerState<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends ConsumerState<EmojiPanel>
    with WidgetsBindingObserver, RouteSettled<EmojiPanel> {
  final _boxKey = GlobalKey();
  var _built = false;
  var _searchStrip = 0.0;
  late final Widget _picker = ZunoEmojiPicker(
    onSelected: widget.controller.insert,
    onBackspace: widget.controller.backspace,
    searchLayout: EmojiSearchLayout.row,
    searching: widget.controller.searching,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
  }

  @override
  void onRouteSettled() => ref.read(emojiCatalogProvider);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  MediaQueryData get _view => MediaQueryData.fromView(View.of(context));

  void _report() {
    final view = _view;
    widget.controller.keyboardInset(view.viewInsets.bottom, view.size);
  }

  @override
  void didChangeMetrics() {
    if (widget.controller._mode == _Mode.search) {
      _searchStrip = _boxKey.currentContext?.size?.height ?? _searchStrip;
    }
    _report();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => KeepClearArea(
    child: ListenableBuilder(
      listenable: widget.controller,
      child: _picker,
      builder: (context, picker) {
        final mode = widget.controller._mode;
        final hidden = mode == _Mode.hidden;
        if (hidden && !_built) return const SizedBox.shrink();
        _built = true;
        final view = _view;
        final padding = view.viewPadding.bottom;
        final height = widget.controller._heightFor(view.size);
        final reserve = math.max(
          0.0,
          height - math.max(view.viewInsets.bottom, padding),
        );
        final pickerHeight = math.max(0.0, height - padding);
        final searching = mode == _Mode.search;
        final box = mode == _Mode.closingSearch
            ? math.max(reserve, _searchStrip)
            : reserve;
        return Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: !hidden,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ConstrainedBox(
                key: _boxKey,
                constraints: BoxConstraints(
                  minHeight: box,
                  maxHeight: searching ? double.infinity : box,
                ),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    fit: searching
                        ? OverflowBoxFit.deferToChild
                        : OverflowBoxFit.max,
                    minHeight: searching ? 0 : pickerHeight,
                    maxHeight: searching ? double.infinity : pickerHeight,
                    child: picker,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class EmojiToggleButton extends StatelessWidget {
  final EmojiPanelController controller;
  final Color? color;

  const EmojiToggleButton({required this.controller, this.color, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final open = controller.open;
      return IconButton(
        icon: Icon(
          open ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
        ),
        tooltip: open
            ? context.l10n.chatShowKeyboard
            : context.l10n.chatShowEmoji,
        color: color,
        onPressed: open ? controller.showKeyboard : controller.showEmoji,
      );
    },
  );
}

class EmojiPanelBackGuard extends ConsumerStatefulWidget {
  final EmojiPanelController controller;
  final Widget child;

  const EmojiPanelBackGuard({
    required this.controller,
    required this.child,
    super.key,
  });

  @override
  ConsumerState<EmojiPanelBackGuard> createState() =>
      _EmojiPanelBackGuardState();
}

class _EmojiPanelBackGuardState extends ConsumerState<EmojiPanelBackGuard> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context) case final route?) markClosableOnReturn(route);
  }

  @override
  Widget build(BuildContext context) {
    final systemBack = ref.watch(platformCapabilitiesProvider).systemBackButton;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) => PopScope(
        canPop: !(systemBack && widget.controller.open),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.controller.close();
        },
        child: child!,
      ),
      child: widget.child,
    );
  }
}

Widget? leaveButton(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.impliesAppBarDismissal) return null;
  return BackButton(onPressed: () => closeOwnRoute(context));
}
