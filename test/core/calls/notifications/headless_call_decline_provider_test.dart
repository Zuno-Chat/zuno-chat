import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/headless_call_decline_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late ProviderContainer container;

  setUp(() async {
    client = buildTestClient(userId: '@me:x');
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
}
