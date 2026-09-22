import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/app.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';

import 'helpers/fake_call_style_channel.dart';
import 'helpers/fake_local_notifications.dart';
import 'helpers/fake_matrix.dart';
import 'helpers/fixed_homeserver.dart';

class _SendCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<User?> getUser(String userId, Room room) async => null;

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}
}

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

  setUp(() async {
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    for (final name in const ['zuno/vibration', 'zuno/calls', 'zuno/share']) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    SharedPreferences.setMockInitialValues({});

    client = Client(
      'test',
      database: _SendCapableFakeDatabaseApi(),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
  });

  testWidgets(
    'a cold-start Decline launch action for the pending ring wins over '
    'showing the ring screen',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const callId = 'call1';

      messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method != 'getNotificationAppLaunchDetails') return null;
        return <String, Object?>{
          'notificationLaunchedApp': true,
          'notificationResponse': <String, Object?>{
            'notificationId': 4002,
            'actionId': 'decline',
            'notificationResponseType': 1,
            'payload': jsonEncode({
              'roomId': room.id,
              'callId': callId,
              'callerId': '@bob:example.org',
              'isVideo': false,
            }),
          },
        };
      });

      final container = ProviderContainer(
        overrides: [
          isLoggedInProvider.overrideWithValue(const AsyncValue.data(false)),
          sharedPreferencesProvider.overrideWithValue(prefs),
          matrixClientProvider.overrideWithValue(client),
          homeserverProvider.overrideWith(
            () => FixedHomeserver(officialHomeserver),
          ),
          registrationSupportProvider.overrideWith(
            (ref) async =>
                const RegistrationSupport(RegistrationAvailability.disabled),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ZunoApp(
            pendingRing: (
              roomId: room.id,
              callId: callId,
              callerId: '@bob:example.org',
              isVideo: false,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(
        container.read(resolvedCallIdsProvider),
        contains(callId),
        reason:
            'the router should have declined the call for real, not '
            'left it to a ring screen that was never shown',
      );
    },
  );
}
