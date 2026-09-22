import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

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

class RecordedNotifications {
  final List<ShownNotification> shown = [];
  final List<ShownNotification> summaries = [];
  final List<int> cancelled = [];
  final List<String> methods = [];
  final List<Map<String, Object?>> channels = [];
  List<Map<String, Object?>> active = const [];

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

RecordedNotifications installFakeLocalNotifications() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final recorded = RecordedNotifications();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(channel, (call) async {
    recorded.methods.add(call.method);
    switch (call.method) {
      case 'show':
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
      case 'getNotificationAppLaunchDetails':
        return <String, Object?>{'notificationLaunchedApp': false};
      case 'createNotificationChannel':
        recorded.channels.add((call.arguments as Map).cast<String, Object?>());
        return true;
      case 'initialize':
        return true;
      default:
        return null;
    }
  });

  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return recorded;
}

void installSilentNotificationSideChannels() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
    'vibration',
    'zuno/conversations',
    'zuno/wake_lock',
  ]) {
    final channel = MethodChannel(name);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
}

class RecordedMethodCalls {
  final List<MethodCall> calls = [];

  Iterable<MethodCall> named(String method) =>
      calls.where((c) => c.method == method);
}

RecordedMethodCalls installFakeConversationsChannel() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/conversations');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final recorded = RecordedMethodCalls();
  messenger.setMockMethodCallHandler(channel, (call) async {
    recorded.calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return recorded;
}
