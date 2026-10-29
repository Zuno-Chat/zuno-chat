import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/app_services.dart';
import 'package:zuno/core/calls/ring_coordinator.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/actions/headless_message_action_provider.dart';
import 'package:zuno/core/notifications/actions/message_notification_action.dart';
import 'package:zuno/core/notifications/local_notifications.dart';
import 'package:zuno/core/notifications/messages/message_notification_provider.dart';
import 'package:zuno/core/security/alerts/security_alerts_provider.dart';

import '../helpers/fake_http.dart';
import '../helpers/fake_matrix.dart';
import '../helpers/preferences_container.dart';

class _SigningIn extends SignInInFlight {
  @override
  bool build() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;
  late List<http.Request> requests;

  setUp(() {
    requests = [];
    client = buildTestClient(
      userId: '@me:example.org',
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);
  });

  Future<ProviderContainer> start({
    required bool signedIn,
    bool signingIn = false,
  }) async {
    final container = await containerWithPreferences(
      {},
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        isLoggedInProvider.overrideWith((ref) => Stream.value(signedIn)),
        firstSyncProvider.overrideWith((ref) async {}),
        if (signingIn) signInInFlightProvider.overrideWith(_SigningIn.new),
      ],
    );
    container.listen(appServicesProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  test('signed out, only the services that outlive a session run', () async {
    final container = await start(signedIn: false);

    expect(container.exists(pushRingServicesProvider), isTrue);
    expect(container.exists(ringCoordinatorProvider), isTrue);
    expect(container.exists(messageNotificationProvider), isFalse);
    expect(container.exists(securityAlertsProvider), isFalse);
  });

  test('signed in, every headless service runs', () async {
    final container = await start(signedIn: true);

    expect(container.exists(pushRingServicesProvider), isTrue);
    expect(container.exists(messageNotificationProvider), isTrue);
    expect(container.exists(headlessMessageActionProvider), isTrue);
    expect(container.exists(securityAlertsProvider), isTrue);
  });

  test('a sign-in still finishing waits before starting them', () async {
    final container = await start(signedIn: true, signingIn: true);

    expect(container.exists(messageNotificationProvider), isFalse);
  });

  test('signed in, a Mark as read handed over from a notification is done '
      'by the app\'s own client', () async {
    await start(signedIn: true);

    LocalNotifications.instance.onMessageActionForTest(
      HandedMessageAction((
        kind: MessageNotificationActionKind.markRead,
        roomId: room.id,
        eventId: r'$last',
        replyText: null,
      )),
    );
    await pumpEventQueue();

    expect(
      jsonDecode(
        requests
            .singleWhere((r) => r.url.pathSegments.contains('read_markers'))
            .body,
      ),
      containsPair('m.read', r'$last'),
    );
  });
}
