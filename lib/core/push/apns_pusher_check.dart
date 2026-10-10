import 'pusher_format.dart';
import 'pusher_info.dart';

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
  final fit = pusherFit(own, gatewayUrl: gatewayUrl);
  return fit.gateway && fit.format
      ? ApnsPusherCheck.matches
      : ApnsPusherCheck.outdated;
}
