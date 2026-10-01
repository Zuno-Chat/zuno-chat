import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/headless_call_decline_provider.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/recording_incoming_call_presenter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late ProviderContainer container;
  late List<Map<String, Object?>> sent;
  late RecordingIncomingCallPresenter presenter;

  setUp(() async {
    sent = [];
    client = buildTestClient(
      userId: '@me:x',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.method == 'PUT' && request.url.path.contains('/send/')) {
          sent.add(jsonDecode(request.body) as Map<String, Object?>);
        }
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    presenter = RecordingIncomingCallPresenter();
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        incomingCallPresenterProvider.overrideWithValue(presenter),
      ],
    );
    addTearDown(container.dispose);
    container.read(headlessCallDeclineProvider);
  });

  test('a decline for a room this device does not know still stops the '
      'ring, and sends nothing', () async {
    CallNotificationService.instance.onHeadlessDeclineForTest(
      const HeadlessCallDecline(roomId: '!unknown:example.org', callId: 'c1'),
    );
    await pumpEventQueue();

    expect(presenter.ends.single.callId, 'c1');
    expect(sent, isEmpty);
  });

  test('a decline from the background declines the call in its room and '
      'marks it resolved', () async {
    final room = buildTestRoom(client);
    client.rooms.add(room);

    CallNotificationService.instance.onHeadlessDeclineForTest(
      HeadlessCallDecline(roomId: room.id, callId: 'c1'),
    );
    await pumpEventQueue(times: 50);

    expect(sent.single['call_id'], 'c1');
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('a decline from the background stops this call\'s ring, though no '
      'ring screen is up to do it', () async {
    final room = buildTestRoom(client);
    client.rooms.add(room);

    CallNotificationService.instance.onHeadlessDeclineForTest(
      HeadlessCallDecline(roomId: room.id, callId: 'c1'),
    );
    await pumpEventQueue(times: 50);

    expect(presenter.ends, [
      (roomId: room.id, callId: 'c1', end: RingEnd.declinedElsewhere),
    ]);
  });

  test('a decline handed over from the action engine is reported done once '
      'it went out', () async {
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    await CallNotificationService.instance.initialize();
    addTearDown(() => IsolateNameServer.removePortNameMapping(declinePortName));
    final room = buildTestRoom(client);
    client.rooms.add(room);

    final handed = await handOffToLiveIsolate(declinePortName, {
      'roomId': room.id,
      'callId': 'c1',
    }).timeout(const Duration(seconds: 5));

    expect(handed, isTrue);
    expect(sent.single['call_id'], 'c1');
  });
}
