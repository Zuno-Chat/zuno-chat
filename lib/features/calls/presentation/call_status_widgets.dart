import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/calls/models/call_quality.dart';

class ConnectionQualityPill extends StatelessWidget {
  final CallQuality quality;

  const ConnectionQualityPill({required this.quality, super.key});

  static String? labelFor(CallQuality quality) => switch (quality) {
    CallQuality.good => null,
    CallQuality.degraded => 'Weak connection',
    CallQuality.poor => 'Poor connection, video reduced',
  };

  @override
  Widget build(BuildContext context) {
    final label = labelFor(quality);
    if (label == null) return const SizedBox.shrink();
    return CallBadge(icon: Icons.network_check, label: label);
  }
}

class CallBadge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? semanticLabel;

  const CallBadge({
    required this.label,
    this.icon,
    this.semanticLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReconnectingNotice extends StatelessWidget {
  const ReconnectingNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Reconnecting…',
      child: ExcludeSemantics(
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Reconnecting…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EncryptingLabel extends StatefulWidget {
  final Duration hintAfter;
  final TextStyle style;
  final TextStyle? hintStyle;
  final CrossAxisAlignment alignment;
  final int? hintMaxLines;
  final DateTime? since;
  final DateTime Function() now;

  const EncryptingLabel({
    this.hintAfter = const Duration(seconds: 8),
    this.style = const TextStyle(color: Colors.white, fontSize: 11),
    this.hintStyle,
    this.alignment = CrossAxisAlignment.end,
    this.hintMaxLines = 3,
    this.since,
    this.now = DateTime.now,
    super.key,
  });

  static const label = 'Encrypting…';
  static const hint =
      'Still encrypting. If this continues, hang up and try again.';

  @override
  State<EncryptingLabel> createState() => _EncryptingLabelState();
}

class _EncryptingLabelState extends State<EncryptingLabel> {
  Timer? _timer;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    final since = widget.since;
    final remaining = since == null
        ? widget.hintAfter
        : widget.hintAfter - widget.now().difference(since);
    if (remaining <= Duration.zero) {
      _showHint = true;
      return;
    }
    _timer = Timer(remaining, () {
      if (mounted) setState(() => _showHint = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Semantics(
      container: true,
      liveRegion: true,
      label: _showHint ? EncryptingLabel.hint : EncryptingLabel.label,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.alignment,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: (style.fontSize ?? 14) + 2,
                  color: style.color,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    EncryptingLabel.label,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_showHint)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  EncryptingLabel.hint,
                  style: widget.hintStyle ?? style,
                  maxLines: widget.hintMaxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: switch (widget.alignment) {
                    CrossAxisAlignment.center => TextAlign.center,
                    CrossAxisAlignment.start => TextAlign.start,
                    _ => TextAlign.end,
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
