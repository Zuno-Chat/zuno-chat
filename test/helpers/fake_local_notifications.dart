import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_method_calls.dart';

class ShownNotification {
  ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String payload;

  Map<String, Object?> android = const {};

  @override
  String toString() =>
      'ShownNotification(id: $id, title: $title, body: $body, '
      'payload: $payload)';
}

const ringNotificationId = 4002;

Map<String, Object?> ringNotificationOnScreen() => {
  'id': ringNotificationId,
  'channelId': 'calls_ringing',
  'groupKey': null,
  'tag': null,
  'title': 'Incoming voice call',
  'body': 'Bob',
  'payload': null,
  'bigText': null,
};

class RecordedNotifications {
  final List<ShownNotification> shown = [];
  final List<ShownNotification> summaries = [];
  final List<int> cancelled = [];
  final List<String> methods = [];
  final List<Map<String, Object?>> channels = [];
  List<Map<String, Object?>> active = const [];
  List<Map<String, Object?>> deviceChannels = const [];
  final List<String> deletedChannels = [];
  Object? showError;
  Map<String, Object?>? initializeArguments;
  Map<String, Object?> launchDetails = const {'notificationLaunchedApp': false};

  void clear() {
    shown.clear();
    summaries.clear();
    cancelled.clear();
    methods.clear();
  }

  Map<String, Object?> get lastPlatformSpecifics {
    expect(shown, isNotEmpty, reason: 'no notification was posted');
    return shown.last.android;
  }

  ShownNotification get single {
    expect(
      shown,
      hasLength(1),
      reason: 'expected exactly one notification, got: $shown',
    );
    return shown.single;
  }
}

RecordedNotifications installFakeLocalNotifications({
  TargetPlatform platform = TargetPlatform.android,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform != platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }
  if (platform == TargetPlatform.iOS) {
    IOSFlutterLocalNotificationsPlugin.registerWith();
  } else {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  }
  final recorded = RecordedNotifications();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(channel, (call) async {
    recorded.methods.add(call.method);
    switch (call.method) {
      case 'show':
        final error = recorded.showError;
        if (error != null) throw error;
        final args = (call.arguments as Map).cast<String, Object?>();
        final specifics = args['platformSpecifics'];
        final android = specifics is Map
            ? specifics.cast<String, Object?>()
            : const <String, Object?>{};
        final notification = ShownNotification(
          id: args['id']! as int,
          title: args['title'] as String?,
          body: args['body'] as String?,
          payload: (args['payload'] as String?) ?? '',
        )..android = android;
        if (android['setAsGroupSummary'] == true) {
          recorded.summaries.add(notification);
        } else {
          recorded.shown.add(notification);
        }
        return null;
      case 'cancel':
        final args = call.arguments;
        recorded.cancelled.add(args is Map ? args['id']! as int : args! as int);
        return null;
      case 'getActiveNotifications':
        return recorded.active;
      case 'getNotificationChannels':
        return recorded.deviceChannels;
      case 'getNotificationAppLaunchDetails':
        return recorded.launchDetails;
      case 'createNotificationChannel':
        recorded.channels.add((call.arguments as Map).cast<String, Object?>());
        return true;
      case 'deleteNotificationChannel':
        recorded.deletedChannels.add(call.arguments as String);
        return null;
      case 'initialize':
        recorded.initializeArguments = (call.arguments as Map)
            .cast<String, Object?>();
        return true;
      default:
        return null;
    }
  });

  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return recorded;
}

void installSilentNotificationSideChannels() => silenceMethodChannels(const [
  'xyz.luan/audioplayers',
  'xyz.luan/audioplayers.global',
  'vibration',
  'zuno/conversations',
  'zuno/wake_lock',
]);

RecordedMethodCalls installFakeConversationsChannel({
  Map<String, String>? noticed,
}) => recordMethodChannel(
  'zuno/conversations',
  reply: (call) {
    if (noticed == null || call.method != 'takePushNotice') return null;
    final args = (call.arguments as Map).cast<String, Object?>();
    final roomId = args['roomId'];
    if (noticed[roomId] != args['eventId']) return false;
    noticed.remove(roomId);
    return true;
  },
);

extension PushNoticeReadings on RecordedMethodCalls {
  List<String> get takenNotices => [
    for (final args in argsOf('takePushNotice').cast<Map<Object?, Object?>>())
      '${args['roomId']}/${args['eventId']}',
  ];
}

Map<String, Object?> deviceChannel(
  String id, {
  required String name,
  required int importance,
}) => {
  'id': id,
  'name': name,
  'description': null,
  'groupId': null,
  'showBadge': true,
  'importance': importance,
  'bypassDnd': false,
  'playSound': importance >= 3,
  'enableLights': false,
  'enableVibration': false,
  'vibrationPattern': null,
  'ledColor': 0,
  'audioAttributesUsage': 5,
};
