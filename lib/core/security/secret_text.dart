import 'dart:async';

import 'package:flutter/material.dart';

import 'screen_security_service.dart';
import 'sensitive_clipboard.dart';

class SecretText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const SecretText(this.text, {this.style, super.key});

  @override
  State<SecretText> createState() => _SecretTextState();
}

class _SecretTextState extends State<SecretText>
    with ScreenProtected<SecretText> {
  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Text(widget.text, style: widget.style),
  );
}

class SecretTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool autofocus;
  final int? minLines;
  final int maxLines;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const SecretTextField({
    required this.controller,
    required this.decoration,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.autofillHints,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  @override
  State<SecretTextField> createState() => _SecretTextFieldState();
}

class _SecretTextFieldState extends State<SecretTextField>
    with ScreenProtected<SecretTextField> {
  final _actions = <Type, Action<Intent>>{
    CopySelectionTextIntent: _SensitiveCopyAction(),
  };

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: _actions,
      child: TextField(
        controller: widget.controller,
        decoration: widget.decoration,
        autofocus: widget.autofocus,
        // shortcut: a screen reader's copy and cut skip SensitiveClipboard, since EditableText's semantics copy calls copySelection directly with no hook, route them through it once Flutter sends them through CopySelectionTextIntent or exposes a hook
        contextMenuBuilder: _secretMenu,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autofillHints: widget.autofillHints,
        keyboardType: widget.keyboardType,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        textCapitalization: TextCapitalization.none,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

Widget _secretMenu(BuildContext context, EditableTextState editable) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: EditableText.getEditableButtonItems(
        clipboardStatus: editable.clipboardStatus.value,
        onCopy: editable.copyEnabled
            ? () => _copy(editable, SelectionChangedCause.toolbar, cut: false)
            : null,
        onCut: editable.cutEnabled
            ? () => _copy(editable, SelectionChangedCause.toolbar, cut: true)
            : null,
        onPaste: editable.pasteEnabled
            ? () => editable.pasteText(SelectionChangedCause.toolbar)
            : null,
        onSelectAll: editable.selectAllEnabled
            ? () => editable.selectAll(SelectionChangedCause.toolbar)
            : null,
        onLookUp: null,
        onSearchWeb: null,
        onShare: null,
        onLiveTextInput: null,
      ),
    );

class _SensitiveCopyAction extends ContextAction<CopySelectionTextIntent> {
  @override
  void invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final editable = context?.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return;
    _copy(editable, intent.cause, cut: intent.collapseSelection);
  }
}

void _copy(
  EditableTextState editable,
  SelectionChangedCause cause, {
  required bool cut,
}) {
  final value = editable.textEditingValue;
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return;
  unawaited(SensitiveClipboard.instance.copy(selection.textInside(value.text)));
  if (cut) {
    editable.userUpdateTextEditingValue(value.replaced(selection, ''), cause);
  }
  if (cause == SelectionChangedCause.toolbar) editable.hideToolbar();
}
