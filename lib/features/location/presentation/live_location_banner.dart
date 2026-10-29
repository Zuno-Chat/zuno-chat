import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_viewing.dart';
import '../../../core/ui/alert_banner.dart';
import 'live_location_map_page.dart';
import 'live_location_stop.dart';
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
    return InfoStrip(
      icon: Icons.share_location_outlined,
      title: liveSharersText(context.l10n, others, includesYou: mine),
      actionLabel: mine ? context.l10n.locationStop : null,
      onAction: () => stopLiveSharingIn(context, ref, room),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LiveLocationMapPage(room: room)),
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
