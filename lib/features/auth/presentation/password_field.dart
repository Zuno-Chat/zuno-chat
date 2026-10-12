import 'package:flutter/material.dart';

import '../../../core/security/screen_security_service.dart';

class PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final bool enabled;
  final bool revealed;
  final VoidCallback? onToggleReveal;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.enabled,
    required this.revealed,
    this.onToggleReveal,
    this.autofillHints,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: !revealed,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        suffixIcon: onToggleReveal == null
            ? null
            : ExcludeFocus(
                child: IconButton(
                  onPressed: enabled ? onToggleReveal : null,
                  tooltip: revealed ? 'Hide password' : 'Show password',
                  icon: Icon(
                    revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
      ),
    );
  }
}

mixin PasswordReveal<T extends StatefulWidget> on State<T> {
  bool passwordRevealed = false;
  VoidCallback? _releaseScreen;

  void togglePasswordReveal() {
    setState(() => passwordRevealed = !passwordRevealed);
    if (passwordRevealed) {
      _releaseScreen = ScreenSecurityService.instance.protect();
    } else {
      _stopProtecting();
    }
  }

  void _stopProtecting() {
    _releaseScreen?.call();
    _releaseScreen = null;
  }

  @override
  void dispose() {
    _stopProtecting();
    super.dispose();
  }
}
