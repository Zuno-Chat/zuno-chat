import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/ui/notice.dart';

Future<void> stopLiveSharingIn(
  BuildContext context,
  WidgetRef ref,
  Room room,
) => attempt(
  context,
  () => ref.read(liveLocationSharingProvider).stopIn(room.id),
  label: 'live location stop',
  failed: context.l10n.locationNotStopped,
);

Future<void> stopAllLiveSharing(BuildContext context, WidgetRef ref) => attempt(
  context,
  ref.read(liveLocationSharingProvider).stopAll,
  label: 'live location stop',
  failed: context.l10n.locationNotStopped,
);
