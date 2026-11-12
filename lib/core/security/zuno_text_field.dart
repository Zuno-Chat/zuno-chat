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
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final bool readOnly;
  final bool? showCursor;
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
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final bool? enabled;

  const ZunoTextField({
    required this.autofillHints,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.readOnly = false,
    this.showCursor,
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
    this.onTap,
    this.inputFormatters,
    this.enabled,
    super.key,
  });

  @override
  Widget build(BuildContext context) => HintNamedField(
    decoration: decoration,
    controller: controller,
    field: _field,
  );

  Widget _field(BuildContext context, TextEditingController controller) =>
      TextField(
        autofillHints: autofillHints,
        controller: controller,
        focusNode: focusNode,
        decoration: decoration,
        textAlignVertical:
            decoration?.prefixIcon != null || decoration?.suffixIcon != null
            ? TextAlignVertical.center
            : null,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        style: style,
        readOnly: readOnly,
        showCursor: showCursor,
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
        onTap: onTap,
        inputFormatters: inputFormatters,
        enabled: enabled,
        enableIMEPersonalizedLearning: KeyboardLearning.allowedIn(context),
      );
}

class HintNamedField extends StatefulWidget {
  final InputDecoration? decoration;
  final TextEditingController? controller;
  final Widget Function(BuildContext context, TextEditingController controller)
  field;

  const HintNamedField({
    required this.decoration,
    required this.controller,
    required this.field,
    super.key,
  });

  @override
  State<HintNamedField> createState() => _HintNamedFieldState();
}

class _HintNamedFieldState extends State<HintNamedField> {
  TextEditingController? _own;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller ?? (_own ??= TextEditingController());
    final decoration = widget.decoration;
    final name = decoration?.labelText == null && decoration?.label == null
        ? decoration?.hintText
        : null;
    return ListenableBuilder(
      listenable: text,
      builder: (context, field) =>
          Semantics(label: text.text.isEmpty ? null : name, child: field),
      child: widget.field(context, text),
    );
  }
}
