import 'package:flutter/material.dart';

Future<bool?> showWhyConfirmSheet(
  BuildContext context, {
  required String name,
  String? unavailableReason,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (_) =>
      WhyConfirmSheet(name: name, unavailableReason: unavailableReason),
);

class WhyConfirmSheet extends StatelessWidget {
  final String name;
  final String? unavailableReason;

  const WhyConfirmSheet({
    required this.name,
    this.unavailableReason,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final unavailableReason = this.unavailableReason;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConfirmDiagram(name: name),
            const SizedBox(height: 20),
            Text(
              'Make sure it is really $name',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              "Encryption keeps your messages to $name's devices, but cannot "
              "tell on its own whether each one is really $name's. A device "
              'someone else added could read along and write as $name.',
              style: body,
            ),
            const SizedBox(height: 8),
            Text(
              "Scan $name's code in person, or compare pictures on a call. "
              'Once per person. If anything changes later, Zuno tells you.',
              style: body,
            ),
            const SizedBox(height: 24),
            if (unavailableReason == null)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Confirm it is really $name'),
              )
            else
              Text(
                unavailableReason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(unavailableReason == null ? 'Not now' : 'Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDiagram extends StatelessWidget {
  final String name;

  const _ConfirmDiagram({required this.name});

  static const _circle = 52.0;
  static const _labelGap = 6.0;
  static const _between = 12.0;
  static const _nodeWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Builder(builder: _diagram),
      ),
    );
  }

  Widget _diagram(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.labelMedium!;
    final labelPainter = TextPainter(
      text: TextSpan(text: name, style: labelStyle),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final labelHeight = labelPainter.height;
    labelPainter.dispose();
    final node = _circle + _labelGap + labelHeight;
    final height = node * 2 + _between;
    final youTop = (height - node) / 2;
    final reach = (_nodeWidth - _circle) / 2;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: youTop),
              child: const _Node(icon: Icons.person_outline, label: 'You'),
            ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ForkPainter(
                        color: colors.outline,
                        fromY: youTop + _circle / 2,
                        toTopY: _circle / 2,
                        toBottomY: node + _between + _circle / 2,
                        reach: reach,
                        rtl: Directionality.of(context) == TextDirection.rtl,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (youTop + _circle) / 2 - 14,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        color: colors.surfaceContainerHigh,
                        child: Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                _Node(icon: Icons.smartphone_outlined, label: name),
                const SizedBox(height: _between),
                const _Node(
                  icon: Icons.question_mark,
                  label: 'Someone else?',
                  unknown: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool unknown;

  const _Node({required this.icon, required this.label, this.unknown = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: _ConfirmDiagram._nodeWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _ConfirmDiagram._circle,
            height: _ConfirmDiagram._circle,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unknown
                  ? colors.surfaceContainerHigh
                  : colors.secondaryContainer,
              border: unknown
                  ? Border.all(color: colors.outline, width: 1.5)
                  : null,
            ),
            child: Icon(
              icon,
              color: unknown ? colors.outline : colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: _ConfirmDiagram._labelGap),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: unknown ? colors.outline : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForkPainter extends CustomPainter {
  final Color color;
  final double fromY;
  final double toTopY;
  final double toBottomY;
  final double reach;
  final bool rtl;

  _ForkPainter({
    required this.color,
    required this.fromY,
    required this.toTopY,
    required this.toBottomY,
    required this.reach,
    required this.rtl,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final start = rtl ? size.width + reach : -reach;
    final end = rtl ? -reach : size.width + reach;
    final from = Offset(start, fromY);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(from, Offset(end, toTopY), paint);

    final delta = Offset(end, toBottomY) - from;
    final step = delta / delta.distance;
    for (var d = 0.0; d < delta.distance; d += 10) {
      canvas.drawLine(from + step * d, from + step * (d + 5), paint);
    }
  }

  @override
  bool shouldRepaint(_ForkPainter old) =>
      old.color != color ||
      old.fromY != fromY ||
      old.toTopY != toTopY ||
      old.toBottomY != toBottomY ||
      old.reach != reach ||
      old.rtl != rtl;
}
