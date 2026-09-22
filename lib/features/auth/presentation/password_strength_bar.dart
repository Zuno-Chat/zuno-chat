import 'package:flutter/material.dart';

import '../../../core/security/password_strength.dart';

class PasswordStrengthBar extends StatelessWidget {
  final String password;
  final String? username;

  const PasswordStrengthBar({required this.password, this.username, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final assessment = assessPassword(password, username: username);

    final filled = switch (assessment.strength) {
      PasswordStrength.unusable => 0,
      PasswordStrength.weak => 1,
      PasswordStrength.fair => 2,
      PasswordStrength.strong => 3,
    };
    final tint = switch (assessment.strength) {
      PasswordStrength.unusable => colors.outlineVariant,
      PasswordStrength.weak => colors.error,
      PasswordStrength.fair => colors.tertiary,
      PasswordStrength.strong => colors.primary,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < filled ? tint : colors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            assessment.blocker == null
                ? assessment.advice
                : '${assessment.blocker}. ${assessment.advice}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  assessment.blocker != null ||
                      assessment.strength == PasswordStrength.weak
                  ? colors.error
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
