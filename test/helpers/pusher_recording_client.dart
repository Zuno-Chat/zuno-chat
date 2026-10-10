import 'dart:async';

import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

class PusherRecordingClient extends Client with PusherRecording {
  PusherRecordingClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  bool signedIn = true;

  @override
  bool isLogged() => signedIn;
}

mixin PusherRecording on Client {
  final posted = <Pusher>[];
  final deleted = <PusherId>[];
  Object? postError;
  Object? deleteError;
  Completer<void>? holdNextPost;
  void Function()? onDeletePusher;
  List<Map<String, Object?>>? pushersOnServer;

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {
    final hold = holdNextPost;
    holdNextPost = null;
    await hold?.future;
    final error = postError;
    if (error != null) throw error;
    posted.add(pusher);
  }

  @override
  Future<void> deletePusher(PusherId pusherId) async {
    onDeletePusher?.call();
    final error = deleteError;
    if (error != null) throw error;
    deleted.add(pusherId);
  }

  @override
  Future<Map<String, Object?>> request(
    RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    if (action != '/client/v3/pushers') {
      return super.request(type, action, data: data, query: query);
    }
    final pushers = pushersOnServer;
    if (pushers == null) throw Exception('offline');
    return {'pushers': pushers};
  }
}

Map<String, Object?> serverPusherJson({
  required String appId,
  required String pushkey,
  String appName = 'Zuno Chat',
  String deviceName = 'Phone',
  Map<String, Object?>? data,
  String? deviceId,
}) => {
  'app_id': appId,
  'pushkey': pushkey,
  'app_display_name': appName,
  'device_display_name': deviceName,
  'kind': 'http',
  'lang': 'en',
  'data': ?data,
  'device_id': ?deviceId,
};
