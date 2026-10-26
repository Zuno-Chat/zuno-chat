import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../core/calls/models/call_quality.dart';
import '../../../core/l10n/l10n.dart';

class ConnectionQualityPill extends StatelessWidget {
  final CallQuality quality;
  final bool sendingVideo;

  const ConnectionQualityPill({
    required this.quality,
    required this.sendingVideo,
    super.key,
  });

  static String? labelFor(
    AppLocalizations l10n,
    CallQuality quality, {
    required bool sendingVideo,
  }) => switch (quality) {
    CallQuality.good => null,
    CallQuality.degraded => l10n.callsConnectionWeak,
    CallQuality.poor when sendingVideo => l10n.callsConnectionPoorVideoReduced,
    CallQuality.poor => l10n.callsConnectionPoor,
  };

  @override
  Widget build(BuildContext context) {
    final label = labelFor(context.l10n, quality, sendingVideo: sendingVideo);
    if (label == null) return const SizedBox.shrink();
    return CallBadge(icon: Icons.network_check, label: label);
  }
}

class CallBadge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? semanticLabel;
  final int maxLines;
  final bool liveRegion;

  const CallBadge({
    required this.label,
    this.icon,
    this.semanticLabel,
    this.maxLines = 1,
    this.liveRegion = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Semantics(
      container: true,
      liveRegion: liveRegion,
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
                    maxLines: maxLines,
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

class ConfirmPersonPill extends StatelessWidget {
  final String name;
  final bool overVideo;
  final VoidCallback onPressed;

  const ConfirmPersonPill({
    required this.name,
    required this.overVideo,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = overVideo ? Colors.white : theme.colorScheme.onSurface;
    final label = context.l10n.verificationConfirmPerson(name);
    const shape = StadiumBorder();
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          color: overVideo
              ? Colors.black54
              : theme.colorScheme.surfaceContainerHigh,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.how_to_reg_outlined, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge!.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: foreground),
                ],
              ),
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
    final label = context.l10n.callsReconnecting;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
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
                label,
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

  const EncryptingLabel({
    this.hintAfter = const Duration(seconds: 8),
    this.style = const TextStyle(color: Colors.white, fontSize: 11),
    this.hintStyle,
    this.alignment = CrossAxisAlignment.end,
    this.hintMaxLines = 3,
    this.since,
    super.key,
  });

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
        : widget.hintAfter - clock.now().difference(since);
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
    final l10n = context.l10n;
    return Semantics(
      container: true,
      liveRegion: true,
      label: _showHint ? l10n.callsEncryptingHint : l10n.callsEncrypting,
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
                    l10n.callsEncrypting,
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
                  l10n.callsEncryptingHint,
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
