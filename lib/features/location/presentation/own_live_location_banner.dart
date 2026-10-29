import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_notice.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/ui/alert_banner.dart';
import 'live_location_stop.dart';

class OwnLiveLocationBanner extends ConsumerWidget {
  final ValueChanged<Room> onOpen;

  const OwnLiveLocationBanner({required this.onOpen, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing = ref.watch(liveLocationSharingProvider);
    final client = ref.watch(matrixClientProvider);
    return ValueListenableBuilder<List<OwnLiveShare>>(
      valueListenable: sharing.shares,
      builder: (context, shares, _) {
        final entries = [
          for (final share in shares)
            if (client.getRoomById(share.roomId) case final room?)
              (room: room, endsAt: share.endsAt),
        ];
        if (entries.isEmpty) return const SizedBox.shrink();
        final notice = liveLocationNotice(context.l10n, entries);
        final only = entries.length == 1 ? entries.single.room : null;
        return InfoStrip(
          icon: Icons.share_location_outlined,
          title: notice.title,
          body: notice.text,
          actionLabel: context.l10n.locationStop,
          onAction: () => stopAllLiveSharing(context, ref),
          onTap: only == null ? null : () => onOpen(only),
        );
      },
    );
  }
}
