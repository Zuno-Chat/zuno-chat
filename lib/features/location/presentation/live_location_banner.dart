import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/live_location_viewing.dart';
import 'live_location_map_page.dart';
import 'live_location_text.dart';
import 'live_location_watch_scope.dart';

class LiveLocationBanner extends ConsumerWidget {
  final Room room;

  const LiveLocationBanner({required this.room, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      LiveLocationWatchScope(roomId: room.id, child: _content(context, ref));

  Widget _content(BuildContext context, WidgetRef ref) {
    final me = room.client.userID;
    final sharers = ref.watch(
      liveSharesProvider(room.id)
          .select((shares) => _Sharers.of(shares, me: me)),
    );
    if (sharers.nobody) return const SizedBox.shrink();
    final mine = sharers.mine;
    final others = [
      for (final userId in sharers.others)
        room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname(),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LiveLocationMapPage(room: room)),
        ),
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
                child: Text(
                  liveSharersText(others, includesYou: mine),
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (mine)
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(liveLocationSharingProvider).stopIn(room.id),
                  child: const Text('Stop'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _Sharers {
  final List<String> others;
  final bool mine;

  const _Sharers(this.others, {required this.mine});

  factory _Sharers.of(List<LiveShareView> shares, {required String? me}) =>
      _Sharers([
        for (final share in shares)
          if (share.userId != me) share.userId,
      ], mine: shares.any((share) => share.userId == me));

  bool get nobody => others.isEmpty && !mine;

  @override
  bool operator ==(Object other) =>
      other is _Sharers &&
      other.mine == mine &&
      listEquals(other.others, others);

  @override
  int get hashCode => Object.hash(mine, Object.hashAll(others));
}
