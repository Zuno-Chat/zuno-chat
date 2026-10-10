import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_preview.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';
import 'package:zuno/core/push/read_model/nse_services.dart';
import 'package:zuno/core/push/read_model/opaque_thread_ids.dart';
import 'package:zuno/core/push/read_model/read_model_publisher.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_megolm_sessions.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late StreamController<bool> logins;
  late ProviderContainer container;

  List<Map<String, Object?>> written(String method) => [
    for (final call in calls)
      if (call.method == method)
        jsonDecode((call.arguments as Map)['json'] as String)
            as Map<String, Object?>,
  ];

  setUp(() async {
    final capabilities = capabilitiesLike(
      iosCapabilities,
      voipRing: true,
      nseNotifications: true,
    );
    ambientCapabilities = capabilities;
    calls = [];
    messenger.setMockMethodCallHandler(nseChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'threadKey' => 'tok-${(call.arguments as Map)['room_id']}',
        'setCredential' => true,
        'takeMarks' || 'readOutcomes' => <Object?>[],
        'syncBadge' => 0,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nseChannel, null));
    addTearDown(OpaqueThreadIds.instance.reset);
    SharedPreferences.setMockInitialValues({
      notificationPreviewKey: NotificationPreview.nothing.name,
    });
    final prefs = await SharedPreferences.getInstance();
    final client =
        buildTestClient(
            userId: '@mwong:zuno.im',
            deviceId: 'PHONE',
            database: SessionStoreFakeDatabaseApi(),
            httpClient: MockClient((_) async => http.Response('{}', 404)),
          )
          ..accessToken = 'syt_token'
          ..homeserver = Uri.parse('https://zuno.im');
    client.rooms.add(
      Room(id: '!r:zuno.im', client: client, membership: Membership.join)
        ..setState(
          StrippedStateEvent(
            type: EventTypes.RoomName,
            senderId: '@mwong:zuno.im',
            stateKey: '',
            content: {'name': 'Design team'},
          ),
        ),
    );
    logins = StreamController<bool>();
    addTearDown(logins.close);
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformCapabilitiesProvider.overrideWithValue(capabilities),
        isLoggedInProvider.overrideWith((ref) => logins.stream),
      ],
    );
    addTearDown(container.dispose);
  });

  test('at Nothing a cold start writes no meta without a level and no room '
      'title', () async {
    container.listen(nseServicesProvider, (_, _) {});
    container.listen(readModelPublisherProvider, (_, _) {});

    logins.add(true);
    await pumpEventQueue(times: 50);

    final metas = written('writeMeta');
    final rooms = written('writeRoom');
    expect(metas, isNotEmpty);
    expect(metas.map((meta) => meta['level']), everyElement(isNotNull));
    expect(metas.first['level'], 'none');
    expect(metas.first['base_url'], 'https://zuno.im');
    expect(rooms, isNotEmpty);
    expect(rooms.map((room) => room['title']), everyElement(''));
  });
}
