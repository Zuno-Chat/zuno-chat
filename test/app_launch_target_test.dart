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
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/security/device_safety.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/auth/presentation/login_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';
import 'package:zuno/features/share/presentation/share_picker_page.dart';

import 'helpers/fake_call_style_channel.dart';
import 'helpers/fake_local_notifications.dart';
import 'helpers/fake_matrix.dart';
import 'helpers/fixed_homeserver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const shareChannel = MethodChannel('zuno/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late List<String> shareCalls;

  setUp(() async {
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    for (final name in const [
      'zuno/vibration',
      'zuno/calls',
      'zuno/shortcuts',
    ]) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(notificationsChannel, null),
    );
    shareCalls = [];
    SharedPreferences.setMockInitialValues({});

    client = buildTestClient(
      userId: '@me:example.org',
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    client.rooms.add(buildTestRoom(client));
  });

  void mockShare(Object? launchShare) {
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shareCalls.add(call.method);
      return call.method == 'takeLaunchShare' ? launchShare : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
  }

  Future<void> pumpApp(WidgetTester tester, {required bool loggedIn}) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        isLoggedInProvider.overrideWithValue(AsyncValue.data(loggedIn)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceRisksProvider.overrideWithValue(
          const AsyncValue.data(<DeviceRisk>{}),
        ),
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
      UncontrolledProviderScope(container: container, child: const ZunoApp()),
    );
  }

  testWidgets('a launch share opens the picker without showing the room list', (
    tester,
  ) async {
    mockShare({'text': 'https://example.org'});
    await pumpApp(tester, loggedIn: true);

    expect(find.byType(RoomListPage), findsNothing);
    expect(find.byType(SharePickerPage), findsNothing);

    for (var i = 0; i < 10; i++) {
      await tester.pump();
      if (find.byType(RoomListPage).evaluate().isNotEmpty) {
        fail('the room list was visible before the picker was on top');
      }
      if (find.byType(SharePickerPage).evaluate().isNotEmpty) break;
    }

    expect(find.byType(SharePickerPage), findsOneWidget);
    expect(find.byType(RoomListPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('with nothing to open, the room list shows', (tester) async {
    mockShare(null);
    await pumpApp(tester, loggedIn: true);
    await tester.pump();
    await tester.pump();

    expect(find.byType(RoomListPage), findsOneWidget);
    expect(find.byType(SharePickerPage), findsNothing);
    expect(shareCalls, ['takeLaunchShare']);
  });

  testWidgets('logged out, a launch share is taken and dropped', (
    tester,
  ) async {
    mockShare({'text': 'https://example.org'});
    await pumpApp(tester, loggedIn: false);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(SharePickerPage), findsNothing);
    expect(shareCalls, ['takeLaunchShare']);
  });
}
