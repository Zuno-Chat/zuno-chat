import 'package:flutter/material.dart';

import '../../../core/calls/models/call_status.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/ui/media_pill.dart';
import '../../../core/ui/zuno_colors.dart';
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
          CallBadge(
            icon: Icons.network_check,
            label: context.l10n.callsConnectionWeak,
          ),
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
            semanticLabel: context.l10n.callsNameMuted(name),
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
  final bool remoteMuted;
  final bool remoteWeak;

  const VideoCallHeader({
    super.key,
    required this.name,
    required this.status,
    this.talkingSince,
    this.encryptingSince,
    this.remoteMuted = false,
    this.remoteWeak = false,
  });

  @override
  Widget build(BuildContext context) {
    const pill = MediaPillSize.regular;
    final label = pill.textStyle(context);
    final talking = status == CallStatus.talking;
    final since = talkingSince;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MediaPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (talking) ...[
                Icon(Icons.lock_outline, semanticLabel: l10n.callsEncrypted),
                SizedBox(width: pill.gap),
              ],
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (remoteMuted) ...[
                SizedBox(width: pill.gap),
                Icon(
                  Icons.mic_off_outlined,
                  semanticLabel: l10n.callsNameMuted(name),
                ),
              ],
              if (talking && since != null)
                Flexible(
                  child: CallTimerSuffix(since: since, style: label),
                ),
            ],
          ),
        ),
        if (!talking) ...[
          const SizedBox(height: 6),
          MediaPill(
            child: CallStatusLine(
              status: status,
              encryptingSince: encryptingSince,
              style: label,
              hintStyle: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: onMediaColor),
              alignment: CrossAxisAlignment.start,
            ),
          ),
        ],
        if (remoteWeak) ...[
          const SizedBox(height: 6),
          CallBadge(icon: Icons.network_check, label: l10n.callsConnectionWeak),
        ],
      ],
    );
  }
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
