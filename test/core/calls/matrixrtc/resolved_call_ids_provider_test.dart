import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;
  late ProviderContainer container;
  late SharedPreferences prefs;
  late RecordedCallStyleCalls callStyle;

  setUp(() async {
    callStyle = installFakeCallStyleChannel();
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => null,
    );
    client = buildTestClient();
    room = buildTestRoom(client);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.read(resolvedCallIdsProvider);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
  });

  test('starts empty', () {
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  test('a call summary marks its call_id resolved', () async {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: summary.toMessageContent(),
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('a call summary also cancels the ring notification', () async {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: summary.toMessageContent(),
      ),
    );
    await pumpEventQueue();
    expect(
      callStyle.calls.map((c) => c.method),
      contains('cancelIncomingCallStyle'),
    );
  });

  test('other event types are ignored', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$invite',
        senderId: '@a:x',
        content: {'msgtype': 'im.zuno.call_invite', 'call_id': 'c1'},
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  test('a summary with no call_id is ignored rather than crashing', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': 'im.zuno.call_summary'},
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  test('multiple resolved calls accumulate', () async {
    for (final callId in ['c1', 'c2']) {
      const missed = CallSummaryStatus.missed;
      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: '\$$callId',
          senderId: '@a:x',
          content: CallSummary(
            callId: callId,
            kind: 'voice',
            status: missed,
            durationMs: 0,
          ).toMessageContent(),
        ),
      );
    }
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), {'c1', 'c2'});
  });

  test('markResolved adds a call_id without needing a summary event', () {
    container.read(resolvedCallIdsProvider.notifier).markResolved('c1');
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('markResolved is idempotent for a call_id already resolved', () async {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: summary.toMessageContent(),
      ),
    );
    await pumpEventQueue();
    container.read(resolvedCallIdsProvider.notifier).markResolved('c1');
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('seeds itself from a resolution stored by another isolate', () async {
    await markCallResolvedOnDisk(prefs, 'from-push');
    final seeded = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(seeded.dispose);

    expect(seeded.read(resolvedCallIdsProvider), contains('from-push'));
  });

  test('markResolved persists for the other isolate to see', () async {
    container.read(resolvedCallIdsProvider.notifier).markResolved('c9');
    await Future<void>.delayed(Duration.zero);

    expect(readResolvedCallIds(prefs), contains('c9'));
  });
}
