import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardLearning extends InheritedWidget {
  final bool allowed;

  const KeyboardLearning({
    required this.allowed,
    required super.child,
    super.key,
  });

  static bool allowedIn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeyboardLearning>()?.allowed ??
      false;

  @override
  bool updateShouldNotify(KeyboardLearning oldWidget) =>
      allowed != oldWidget.allowed;
}

class ZunoTextField extends StatelessWidget {
  final Iterable<String>? autofillHints;
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final bool readOnly;
  final bool canRequestFocus;
  final bool autofocus;
  final bool obscureText;
  final bool? autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool? enabled;

  const ZunoTextField({
    required this.autofillHints,
    this.controller,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.readOnly = false,
    this.canRequestFocus = true,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.enabled,
    super.key,
  });

  @override
  Widget build(BuildContext context) => TextField(
    autofillHints: autofillHints,
    controller: controller,
    decoration: decoration,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    textCapitalization: textCapitalization,
    style: style,
    readOnly: readOnly,
    canRequestFocus: canRequestFocus,
    autofocus: autofocus,
    obscureText: obscureText,
    autocorrect: autocorrect,
    enableSuggestions: enableSuggestions,
    maxLines: maxLines,
    minLines: minLines,
    maxLength: maxLength,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    inputFormatters: inputFormatters,
    enabled: enabled,
    enableIMEPersonalizedLearning: KeyboardLearning.allowedIn(context),
  );
}
