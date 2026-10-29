import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_viewing.dart';
import 'live_location_clock.dart';
import 'live_location_stop.dart';
import 'live_location_text.dart';
import 'location_map_view.dart';
import 'map_parts.dart';

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
      DateLabels.of(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MapPreviewFrame(
          preview: position == null
              ? const _Waiting()
              : LocationMapView(
                  geo: position.geo,
                  interactive: false,
                  persistTiles: false,
                ),
          radius: radius,
          onTap: onOpen,
          icon: Icons.share_location_outlined,
          caption: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.locationLiveLocation),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          trailing: trailing,
        ),
        if (share.userId == room.client.userID)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => stopLiveSharingIn(context, ref, room),
              child: Text(context.l10n.locationStopSharing),
            ),
          ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => MapGrid(
    child: Center(
      child: Icon(
        Icons.share_location_outlined,
        size: 32,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
