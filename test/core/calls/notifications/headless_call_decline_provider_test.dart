import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/headless_call_decline_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late ProviderContainer container;
  late List<Map<String, Object?>> sent;

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
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.read(headlessCallDeclineProvider);
  });

  test(
    'a decline for an unknown room is a no-op rather than a crash',
    () async {
      CallNotificationService.instance.onHeadlessDeclineForTest(
        const HeadlessCallDecline(roomId: '!unknown:example.org', callId: 'c1'),
      );
      await pumpEventQueue();
      expect(container.read(resolvedCallIdsProvider), isEmpty);
    },
  );

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
}
