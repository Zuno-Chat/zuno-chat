import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/live_location_viewing.dart';
import 'live_location_clock.dart';
import 'live_location_text.dart';
import 'location_map_view.dart';
import 'map_parts.dart';

const _previewAspectRatio = 16 / 10;

class LiveLocationTile extends ConsumerWidget {
  final Room room;
  final LiveShareView share;
  final double radius;
  final Color muted;
  final Widget trailing;
  final VoidCallback onOpen;

  const LiveLocationTile({
    required this.room,
    required this.share,
    required this.radius,
    required this.muted,
    required this.trailing,
    required this.onOpen,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final position = share.position;
    final status = liveShareStatusText(
      share,
      watchLiveNow(ref),
      liveClockFormat(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AspectRatio(
              aspectRatio: _previewAspectRatio,
              child: position == null
                  ? const _Waiting()
                  : LocationMapView(
                      geo: position.geo,
                      interactive: false,
                      persistTiles: false,
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(7, 6, 7, 3),
          child: Row(
            children: [
              const Icon(Icons.share_location_outlined, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Live location'),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
        if (share.userId == room.client.userID)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () =>
                  ref.read(liveLocationSharingProvider).stopIn(room.id),
              child: const Text('Stop sharing'),
            ),
          ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: MapGridPainter(
        background: colors.surfaceContainerHighest,
        line: colors.outlineVariant,
      ),
      child: Center(
        child: Icon(
          Icons.share_location_outlined,
          size: 32,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
