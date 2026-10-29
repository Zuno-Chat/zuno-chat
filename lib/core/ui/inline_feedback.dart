import 'package:flutter/material.dart';

import '../l10n/display_text.dart';

class InlineSpinner extends StatelessWidget {
  final double size;
  final double padding;

  const InlineSpinner({this.size = 20, super.key}) : padding = 0;

  const InlineSpinner.icon({super.key}) : size = 24, padding = 2;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: const CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class InlineError extends StatelessWidget {
  final String message;
  final TextAlign? textAlign;

  const InlineError(@displayText this.message, {this.textAlign, super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      textAlign: textAlign,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
