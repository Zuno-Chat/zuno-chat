import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import 'pusher_info.dart';

Future<List<PusherInfo>?> fetchPushers(Client client) async {
  final Map<String, Object?> response;
  try {
    response = await client.request(RequestType.GET, '/client/v3/pushers');
  } catch (e, s) {
    reportCaught('pusher list fetch', e, s);
    return null;
  }
  final raw = response['pushers'];
  if (raw is! List) {
    debugPrint('zuno/push: pusher list response had no pushers array');
    return null;
  }
  return raw
      .whereType<Map<String, Object?>>()
      .map(PusherInfo.fromJson)
      .toList();
}

enum PusherCheck { matches, missing, outdated, unknown }

Future<PusherCheck> checkPusherOnServer(
  Client client, {
  required String appId,
  required String pushkey,
  required Uri? gatewayUrl,
}) async {
  final pushers = await fetchPushers(client);
  if (pushers == null) return PusherCheck.unknown;
  final own = pushers
      .where((pusher) => pusher.appId == appId && pusher.pushkey == pushkey)
      .firstOrNull;
  if (own == null) return PusherCheck.missing;
  final fit = pusherFit(own, gatewayUrl: gatewayUrl);
  return fit.gateway && fit.format ? PusherCheck.matches : PusherCheck.outdated;
}
