import 'apns_pusher.dart' show apnsPusherFormat;
import 'pusher_info.dart';

export 'apns_pusher.dart' show apnsPusherFormat;

enum ApnsPusherCheck { matches, missing, outdated, unknown }

ApnsPusherCheck checkApnsPusher(
  List<PusherInfo>? pushers, {
  required String appId,
  required String pushkey,
  required Uri? gatewayUrl,
}) {
  if (pushers == null) return ApnsPusherCheck.unknown;
  final own = pushers
      .where((pusher) => pusher.appId == appId && pusher.pushkey == pushkey)
      .firstOrNull;
  if (own == null) return ApnsPusherCheck.missing;
  if (own.format != apnsPusherFormat) return ApnsPusherCheck.outdated;
  if (gatewayUrl != null && Uri.tryParse(own.url ?? '') != gatewayUrl) {
    return ApnsPusherCheck.outdated;
  }
  return ApnsPusherCheck.matches;
}
