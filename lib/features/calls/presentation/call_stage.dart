import 'package:flutter/material.dart';

import 'call_status_line.dart';
import 'call_status_widgets.dart';

class VoiceCallStage extends StatelessWidget {
  final Widget Function(double radius) avatarBuilder;
  final String name;
  final CallStatus status;
  final DateTime? talkingSince;
  final DateTime? encryptingSince;
  final bool remoteMuted;
  final bool remoteWeak;

  const VoiceCallStage({
    super.key,
    required this.avatarBuilder,
    required this.name,
    required this.status,
    this.talkingSince,
    this.encryptingSince,
    this.remoteMuted = false,
    this.remoteWeak = false,
  });

  @override
  Widget build(BuildContext context) {
    return CallPortrait(
      avatarBuilder: avatarBuilder,
      name: name,
      muted: remoteMuted,
      details: [
        CallStatusLine(
          status: status,
          talkingSince: talkingSince,
          encryptingSince: encryptingSince,
        ),
        if (remoteWeak) ...[
          const SizedBox(height: 12),
          const CallBadge(icon: Icons.network_check, label: 'Weak connection'),
        ],
      ],
    );
  }
}

class CallPortrait extends StatelessWidget {
  final Widget Function(double radius) avatarBuilder;
  final String name;
  final bool muted;
  final List<Widget> details;

  const CallPortrait({
    super.key,
    required this.avatarBuilder,
    required this.name,
    required this.details,
    this.muted = false,
  });

  static const _shortStage = 300.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (muted) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.mic_off_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: '$name is muted',
          ),
        ],
      ],
    );
    final caption = <Widget>[title, const SizedBox(height: 6), ...details];
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < _shortStage;
        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 32,
              vertical: short ? 4 : 16,
            ),
            child: short
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      avatarBuilder(36),
                      const SizedBox(width: 20),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: caption,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      avatarBuilder(64),
                      const SizedBox(height: 20),
                      ...caption,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class VideoCallHeader extends StatelessWidget {
  final String name;
  final CallStatus status;
  final DateTime? talkingSince;
  final DateTime? encryptingSince;
  final DateTime Function() now;
  final bool remoteMuted;
  final bool remoteWeak;

  const VideoCallHeader({
    super.key,
    required this.name,
    required this.status,
    this.talkingSince,
    this.encryptingSince,
    this.now = DateTime.now,
    this.remoteMuted = false,
    this.remoteWeak = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge!.copyWith(color: Colors.white);
    final talking = status == CallStatus.talking;
    final since = talkingSince;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pill(
          radius: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (talking) ...[
                const Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: Colors.white,
                  semanticLabel: 'Encrypted',
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: label,
                ),
              ),
              if (remoteMuted) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.mic_off_outlined,
                  size: 16,
                  color: Colors.white,
                  semanticLabel: '$name is muted',
                ),
              ],
              if (talking && since != null)
                Flexible(
                  child: CallTimerSuffix(since: since, now: now, style: label),
                ),
            ],
          ),
        ),
        if (!talking) ...[
          const SizedBox(height: 6),
          _Pill(
            radius: 14,
            child: CallStatusLine(
              status: status,
              encryptingSince: encryptingSince,
              now: now,
              style: label,
              hintStyle: theme.textTheme.bodySmall!.copyWith(
                color: Colors.white,
              ),
              alignment: CrossAxisAlignment.start,
            ),
          ),
        ],
        if (remoteWeak) ...[
          const SizedBox(height: 6),
          const CallBadge(icon: Icons.network_check, label: 'Weak connection'),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final double radius;
  final Widget child;

  const _Pill({required this.radius, required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    borderRadius: BorderRadius.circular(radius),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: child,
    ),
  );
}

class CallGrid extends StatelessWidget {
  final List<Widget> tiles;

  const CallGrid({super.key, required this.tiles});

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (tiles.length / 2).ceil();
        final width = (constraints.maxWidth - _gap) / 2;
        final height = (constraints.maxHeight - _gap * (rows - 1)) / rows;

        double leftOf(int index) {
          final aloneOnLastRow =
              tiles.length.isOdd && index == tiles.length - 1;
          if (aloneOnLastRow) return (constraints.maxWidth - width) / 2;
          return index.isEven ? 0 : width + _gap;
        }

        return Stack(
          children: [
            for (final (index, tile) in tiles.indexed)
              Positioned(
                key: tile.key == null ? null : ValueKey(('cell', tile.key)),
                left: leftOf(index),
                top: (index ~/ 2) * (height + _gap),
                width: width,
                height: height,
                child: tile,
              ),
          ],
        );
      },
    );
  }
}
