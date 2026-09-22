import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/zuno_theme.dart';

class SecurityStatusCard extends ConsumerWidget {
  final void Function(AccountSecurityStatus status) onAction;
  const SecurityStatusCard({required this.onAction, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(accountSecurityStatusProvider);
    return status.when(
      loading: () => const _CardShell(
        icon: Icons.shield_outlined,
        title: 'Checking…',
        body: '',
      ),
      error: (_, _) => const _CardShell(
        icon: Icons.shield_outlined,
        title: 'Could not check right now',
        body: 'It usually clears once you reconnect.',
      ),
      data: (value) {
        final copy = accountSecurityCopy(value);
        final attention = value != AccountSecurityStatus.protected;
        return _CardShell(
          icon: securityStatusIcon(attention: attention),
          attention: attention,
          title: copy.title,
          body: copy.body,
          action: copy.action == null
              ? null
              : FilledButton(
                  onPressed: () => onAction(value),
                  child: Text(copy.action!),
                ),
        );
      },
    );
  }
}

class _CardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final bool attention;

  const _CardShell({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = attention
        ? colors.errorContainer
        : colors.surfaceContainerHigh;
    final onTint = attention ? colors.onErrorContainer : colors.onSurface;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: tint,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZunoRadius.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (attention) const AttentionStripe(),
            Expanded(child: _content(context, onTint)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color onTint) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: onTint),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(color: onTint),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: textTheme.bodyMedium?.copyWith(color: onTint),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
