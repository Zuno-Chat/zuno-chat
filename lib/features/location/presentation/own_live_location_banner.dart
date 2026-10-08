import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/location/live_location_notice.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/matrix/matrix_client_provider.dart';

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
        final notice = liveLocationNotice(entries);
        final only = entries.length == 1 ? entries.single.room : null;
        final scheme = Theme.of(context).colorScheme;
        final text = TextStyle(color: scheme.onSecondaryContainer);
        return Material(
          color: scheme.secondaryContainer,
          child: InkWell(
            onTap: only == null ? null : () => onOpen(only),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.share_location_outlined,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice.title,
                          style: text.copyWith(fontWeight: FontWeight.w500),
                        ),
                        Text(notice.text, style: text),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: sharing.stopAll,
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
