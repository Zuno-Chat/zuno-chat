import 'package:flutter/material.dart';

class QuotedMessageBox extends StatelessWidget {
  final String senderName;
  final String snippet;
  final IconData? icon;
  final Widget? thumbnail;
  final double borderRadius;
  final Color? fill;
  final Color? muted;

  const QuotedMessageBox({
    required this.senderName,
    required this.snippet,
    this.icon,
    this.thumbnail,
    this.borderRadius = 8,
    this.fill,
    this.muted,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = this.muted ?? colors.onSurfaceVariant;
    final snippetStyle = textTheme.bodySmall?.copyWith(color: muted);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: fill ?? colors.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: colors.primary),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 5, 10, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (icon == null)
                        Text(
                          snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: snippetStyle,
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 14, color: muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                snippet,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: snippetStyle,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (thumbnail != null) ...[
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(width: 36, height: 36, child: thumbnail),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
