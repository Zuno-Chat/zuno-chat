import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import 'pusher_info.dart';

Future<List<PusherInfo>?> fetchPushers(Client client) async {
  final Map<String, Object?> response;
  try {
    response = await client.request(RequestType.GET, '/client/v3/pushers');
  } catch (e) {
    debugPrint('zuno/push: could not read the pusher list ($e)');
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

Future<bool?> pusherIsRegistered(
  Client client, {
  required String appId,
  required String pushkey,
}) async {
  final pushers = await fetchPushers(client);
  if (pushers == null) return null;
  return pushers.any(
    (pusher) => pusher.appId == appId && pusher.pushkey == pushkey,
  );
}
