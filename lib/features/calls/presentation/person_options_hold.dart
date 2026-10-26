import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';

class PersonOptionsHold extends StatelessWidget {
  final VoidCallback? onLongPress;
  final Widget child;

  const PersonOptionsHold({
    required this.onLongPress,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null
          ? null
          : context.l10n.callsPersonOptions,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}
