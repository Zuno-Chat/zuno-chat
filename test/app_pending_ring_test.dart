import 'dart:convert';

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
import 'helpers/native_method_calls.dart';
import 'helpers/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;

  setUp(() async {
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    silenceMethodChannels(const ['zuno/vibration', 'zuno/calls', 'zuno/share']);
    SharedPreferences.setMockInitialValues({});

    client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);
  });

  testWidgets(
    'a cold-start Decline launch action for the pending ring wins over '
    'showing the ring screen',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const callId = 'call1';

      installFakeLocalNotifications().launchDetails = {
        'notificationLaunchedApp': true,
        'notificationResponse': <String, Object?>{
          'notificationId': ringNotificationId,
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
      await pumpUntil(
        tester,
        () => container.read(resolvedCallIdsProvider).contains(callId),
        reason:
            'the router to decline the call for real, not leave it to a ring '
            'screen that was never shown',
      );

      expect(find.byType(IncomingCallPage), findsNothing);
    },
  );
}
