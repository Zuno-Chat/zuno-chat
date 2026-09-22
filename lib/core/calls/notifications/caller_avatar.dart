import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import '../../matrix/bearer_authorization.dart';

const callerAvatarTimeout = Duration(seconds: 8);

Future<Uint8List?> fetchCallerAvatarBytes(
  Client client,
  Uri? avatarUrl, {
  Future<Uint8List> Function(Uri uri)? download,
  Duration timeout = callerAvatarTimeout,
}) async {
  if (avatarUrl == null) return null;
  final fetch = download ?? (uri) => _downloadViaHttpClient(client, uri);
  try {
    final thumbnailUri = await avatarUrl.getThumbnailUri(
      client,
      width: 128,
      height: 128,
    );
    return await fetch(thumbnailUri).timeout(timeout);
  } catch (e) {
    debugPrint('zuno/notifications: could not fetch caller avatar: $e');
    return null;
  }
}

Future<Uint8List> _downloadViaHttpClient(Client client, Uri uri) async {
  final response = await client.httpClient.get(
    uri,
    headers: {'authorization': await bearerAuthorization(client)},
  );
  if (response.statusCode != 200) {
    throw Exception('Avatar fetch failed: HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}
