import 'package:flutter/material.dart';

import '../l10n/display_text.dart';
import '../security/zuno_text_field.dart';

class SearchField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextInputAction? textInputAction;

  const SearchField({
    @displayText required this.hint,
    this.controller,
    this.onChanged,
    this.autofocus = false,
    this.textInputAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ZunoTextField(
    autofillHints: null,
    controller: controller,
    autofocus: autofocus,
    textInputAction: textInputAction,
    onChanged: onChanged,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: hint,
    ),
  );
}
