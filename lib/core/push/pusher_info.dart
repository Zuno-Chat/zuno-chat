import 'fcm_pusher.dart';
import 'unified_push_pusher.dart';

class PusherInfo {
  final String appId;
  final String pushkey;
  final String appDisplayName;
  final String deviceDisplayName;
  final String kind;
  final String lang;
  final String? profileTag;
  final String? url;
  final String? format;

  final String? deviceId;

  const PusherInfo({
    required this.appId,
    required this.pushkey,
    required this.appDisplayName,
    required this.deviceDisplayName,
    required this.kind,
    required this.lang,
    this.profileTag,
    this.url,
    this.format,
    this.deviceId,
  });

  factory PusherInfo.fromJson(Map<String, Object?> json) {
    String? maybeString(Object? value) => value is String ? value : null;
    final data = json['data'] is Map ? json['data'] as Map : const {};
    return PusherInfo(
      appId: maybeString(json['app_id']) ?? '',
      pushkey: maybeString(json['pushkey']) ?? '',
      appDisplayName: maybeString(json['app_display_name']) ?? '',
      deviceDisplayName: maybeString(json['device_display_name']) ?? '',
      kind: maybeString(json['kind']) ?? '',
      lang: maybeString(json['lang']) ?? '',
      profileTag: maybeString(json['profile_tag']),
      url: maybeString(data['url']),
      format: maybeString(data['format']),
      deviceId: maybeString(json['device_id']),
    );
  }
}

class PusherGroups {
  final PusherInfo? currentSession;

  final List<PusherInfo> others;

  const PusherGroups({required this.currentSession, required this.others});
}

const zunoPusherAppIds = {unifiedPushAppId, fcmAppId};

bool _isCurrentDevice(PusherInfo pusher, String? currentPushkey) =>
    currentPushkey != null &&
    zunoPusherAppIds.contains(pusher.appId) &&
    pusher.pushkey == currentPushkey;

PusherGroups groupPushers(List<PusherInfo> pushers, String? currentPushkey) {
  PusherInfo? currentSession;
  final others = <PusherInfo>[];
  for (final pusher in pushers) {
    if (currentSession == null && _isCurrentDevice(pusher, currentPushkey)) {
      currentSession = pusher;
    } else {
      others.add(pusher);
    }
  }
  return PusherGroups(currentSession: currentSession, others: others);
}
