import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../errors/caught_errors.dart';
import '../../l10n/l10n.dart';
import '../../platform/os_version.dart';
import '../../platform/platform_capabilities.dart';

enum NotificationPreview {
  full('full'),
  nameOnly('name'),
  nothing('none');

  const NotificationPreview(this.wire);

  final String wire;

  String label(AppLocalizations l10n) => switch (this) {
    full => l10n.notificationsPreviewFull,
    nameOnly => l10n.notificationsPreviewNameOnly,
    nothing => l10n.notificationsPreviewNothing,
  };

  String description(AppLocalizations l10n) => switch (this) {
    full => l10n.notificationsPreviewFullDescription,
    nameOnly => l10n.notificationsPreviewNameOnlyDescription,
    nothing => l10n.notificationsPreviewNothingDescription,
  };

  String callName(String name, AppLocalizations l10n) =>
      this == nothing ? l10n.callsGenericRingName : name;

  bool get showsSenders => this != nothing;

  bool get showsImages => this == full;
}

const notificationPreviewKey = 'settings.notification_preview';
const notificationPreviewHintKey = 'settings.notification_preview_hint_done';
const previewThread = 'zuno';

NotificationPreview notificationPreviewFromPreferences(
  SharedPreferences prefs,
) {
  final stored = prefs.getString(notificationPreviewKey);
  return NotificationPreview.values.firstWhere(
    (level) => level.name == stored,
    orElse: () => NotificationPreview.full,
  );
}

Future<NotificationPreview> currentNotificationPreview() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return notificationPreviewFromPreferences(prefs);
  } catch (e, s) {
    reportCaught('notification preview read', e, s);
    return NotificationPreview.full;
  }
}

const _retentionFixes = <int, String>{
  15: '15.8.8',
  16: '16.7.16',
  18: '18.7.8',
  26: '26.4.2',
};

bool notificationRetentionUnpatched(String osVersion) {
  final major = osVersionParts(osVersion)?.first;
  if (major == 17) return true;
  final fixed = _retentionFixes[major];
  return fixed != null && !osAtLeast(osVersion, fixed);
}

final notificationRetentionUnpatchedProvider = Provider<bool>(
  (ref) =>
      ref.watch(platformCapabilitiesProvider).notificationRetentionCheck &&
      notificationRetentionUnpatched(ref.watch(operatingSystemVersionProvider)),
);
