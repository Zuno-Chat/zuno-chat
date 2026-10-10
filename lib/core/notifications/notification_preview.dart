import 'package:shared_preferences/shared_preferences.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

enum NotificationPreview {
  full('full', 'Name and message', 'Who wrote and what they said'),
  nameOnly('name', 'Name only', 'Who wrote, without the message'),
  nothing('none', 'Nothing', 'Only that something new arrived');

  const NotificationPreview(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;
}

const notificationPreviewKey = 'settings.notification_preview';
const notificationPreviewHintKey = 'settings.notification_preview_hint_done';
const previewThread = 'zuno';
const previewNothingTitle = 'Zuno';
const previewHiddenText = 'New message';

NotificationPreview notificationPreviewFromPreferences(
  SharedPreferences prefs,
) {
  final stored = prefs.getString(notificationPreviewKey);
  return NotificationPreview.values.firstWhere(
    (level) => level.name == stored,
    orElse: () => NotificationPreview.full,
  );
}

Future<NotificationPreview> currentNotificationPreview({
  PlatformCapabilities? capabilities,
}) async {
  if (!(capabilities ?? ambientCapabilities).nseNotifications) {
    return NotificationPreview.full;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return notificationPreviewFromPreferences(prefs);
  } catch (e, s) {
    reportCaught('notification preview read', e, s);
    return NotificationPreview.full;
  }
}

const _retentionFixes = <int, List<int>>{
  15: [15, 8, 8],
  16: [16, 7, 16],
  18: [18, 7, 8],
  26: [26, 4, 2],
};

bool notificationRetentionUnpatched(String osVersion) {
  final match = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(osVersion);
  if (match == null) return false;
  final version = [
    for (var group = 1; group <= 3; group++)
      int.tryParse(match.group(group) ?? '0') ?? 0,
  ];
  if (version[0] == 17) return true;
  final fixed = _retentionFixes[version[0]];
  if (fixed == null) return false;
  for (var part = 0; part < 3; part++) {
    if (version[part] != fixed[part]) return version[part] < fixed[part];
  }
  return false;
}
