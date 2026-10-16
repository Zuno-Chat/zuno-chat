import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

const attentionStripeWidth = 4.0;

class AttentionStripe extends StatelessWidget {
  const AttentionStripe({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: attentionStripeWidth,
    color: Theme.of(context).colorScheme.error,
  );
}

enum AlertBannerTone { attention, notice }

class AlertBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? detail;
  final String? footnote;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final AlertBannerTone tone;

  const AlertBanner({
    required this.icon,
    required this.title,
    this.body,
    this.detail,
    this.footnote,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.tone = AlertBannerTone.attention,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final attention = tone == AlertBannerTone.attention;
    final background = attention
        ? colors.errorContainer
        : colors.secondaryContainer;
    final foreground = attention
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: foreground);
    final body = this.body;
    final detail = this.detail;
    final footnote = this.footnote;
    final actionLabel = this.actionLabel;

    return Material(
      color: background,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (attention) const AttentionStripe(),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  12,
                  12,
                  onDismiss == null ? 16 : 4,
                  actionLabel == null ? 12 : 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: foreground),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: foreground,
                            ),
                          ),
                          if (body != null) ...[
                            const SizedBox(height: 2),
                            Text(body, style: textStyle),
                          ],
                          if (detail != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: foreground,
                              ),
                            ),
                          ],
                          if (footnote != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              footnote,
                              style: textStyle?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          if (actionLabel != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: foreground,
                                  foregroundColor: background,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: onAction,
                                child: Text(actionLabel),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onDismiss != null)
                      IconButton(
                        icon: const Icon(Icons.close),
                        color: foreground,
                        tooltip: context.l10n.commonDismiss,
                        visualDensity: VisualDensity.compact,
                        onPressed: onDismiss,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
