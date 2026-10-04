import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/message_notification_action.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/security/security_prompt.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/communities/presentation/community_page.dart';
import 'package:zuno/features/onboarding/presentation/onboarding_flow_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';
import 'package:zuno/features/settings/presentation/settings_page.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../verification/presentation/verification_harness.dart';

class _SyncStubClient extends Client {
  _SyncStubClient({required super.httpClient})
    : super('test', database: TimelineCapableFakeDatabaseApi());

  Object? syncError;
  int syncs = 0;
  bool withEncryption = false;

  late final Encryption _encryption = Encryption(client: this);

  @override
  Encryption? get encryption => withEncryption ? _encryption : null;

  @override
  Future<void> abortSync() async {}

  @override
  Future<void> oneShotSync({Duration? timeout}) async {
    syncs++;
    final error = syncError;
    if (error != null) throw error;
  }

  @override
  set backgroundSync(bool enabled) {}
}

void main() {
  late _SyncStubClient client;
  late Room room;
  late List<http.Request> requests;
  late bool offline;
  late StreamController<KeyVerification> verifications;

  setUp(() {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      MethodChannel('dexterous.com/flutter/local_notifications'),
      MethodChannel('zuno/calls'),
      MethodChannel('com.llfbandit.record/messages'),
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'initialize' ? true : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    requests = [];
    offline = false;
    verifications = StreamController<KeyVerification>.broadcast();
    addTearDown(verifications.close);
    client = _SyncStubClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        if (offline) {
          throw http.ClientException('Failed host lookup', request.url);
        }
        return http.Response('{}', 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client, notificationCount: 2)..partial = false;
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        senderId: '@bob:example.org',
        stateKey: '',
        content: {'name': 'Book club'},
      ),
    );
    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$last',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'See you at 8'},
    );
    client.rooms.add(room);
  });

  Future<ProviderContainer> pumpRoomList(
    WidgetTester tester, {
    List<OnboardingStep> onboarding = const [],
    Future<List<OnboardingStep>> Function()? onboardingBuild,
    SecurityPromptDecision prompt = SecurityPromptDecision.none,
    Map<String, Object> stored = const {},
    bool settle = true,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        onboardingStepsProvider.overrideWith(
          (ref) => onboardingBuild?.call() ?? Future.value(onboarding),
        ),
        securityPromptProvider.overrideWith((ref) async => prompt),
        incomingKeyVerificationProvider.overrideWith(
          (ref) => verifications.stream,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: const RoomListPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  Future<void> network(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> bounded(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Iterable<http.Request> requestsTo(String segment) =>
      requests.where((r) => r.url.pathSegments.contains(segment));

  Future<void> openActions(WidgetTester tester) async {
    await tester.longPress(find.text('Book club'));
    await tester.pumpAndSettle();
  }

  void mute() {
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            {
              'rule_id': room.id,
              'default': false,
              'enabled': true,
              'actions': <Object>[],
              'conditions': [
                {'kind': 'event_match', 'key': 'room_id', 'pattern': room.id},
              ],
            },
          ],
        },
      },
    );
  }

  group('the actions on a chat', () {
    testWidgets('an unread chat can be marked read', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      expect(find.text('Mark as read'), findsOneWidget);
      await tester.tap(find.text('Mark as read'));
      await network(tester);

      expect(
        jsonDecode(requestsTo('read_markers').single.body),
        allOf(
          containsPair('m.fully_read', r'$last'),
          containsPair('m.read', r'$last'),
        ),
      );
    });

    testWidgets('a read chat offers no mark as read', (tester) async {
      room.notificationCount = 0;
      await pumpRoomList(tester);
      await openActions(tester);

      expect(find.text('Mark as read'), findsNothing);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Leave room'), findsOneWidget);
    });

    testWidgets('Mute silences the chat on the server', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      await tester.tap(find.text('Mute'));
      await network(tester);

      final rule = requestsTo('pushrules').single;
      expect(rule.method, 'PUT');
      expect(rule.url.pathSegments, contains('override'));
    });

    testWidgets('a muted chat offers Unmute instead', (tester) async {
      mute();
      await pumpRoomList(tester);
      await openActions(tester);

      expect(find.text('Mute'), findsNothing);
      await tester.tap(find.text('Unmute'));
      await network(tester);

      expect(requestsTo('pushrules').single.method, 'DELETE');
    });

    testWidgets('leaving asks first', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      expect(find.text('Leave room?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await network(tester);

      expect(requestsTo('leave'), hasLength(1));
    });

    testWidgets('closing the sheet does nothing', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      await tester.tapAt(const Offset(10, 10));
      await network(tester);

      expect(requests, isEmpty);
    });

    testWidgets('muting offline says what failed, not the error', (
      tester,
    ) async {
      await pumpRoomList(tester);
      await openActions(tester);
      offline = true;

      await tester.tap(find.text('Mute'));
      await network(tester);

      expect(
        find.text('Not muted. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('unmuting and marking read offline say so too', (tester) async {
      mute();
      await pumpRoomList(tester);
      offline = true;

      await openActions(tester);
      await tester.tap(find.text('Unmute'));
      await network(tester);
      expect(
        find.text('Not unmuted. Check your connection and try again.'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(tester.element(find.byType(RoomListPage)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await openActions(tester);
      await tester.tap(find.text('Mark as read'));
      await network(tester);
      expect(
        find.text('Not marked as read. Check your connection and try again.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Mark as read handed over from a notification is done by the '
      'app\'s own client', (tester) async {
    await pumpRoomList(tester);

    CallNotificationService.instance.onMessageActionForTest(
      HandedMessageAction((
        kind: MessageNotificationActionKind.markRead,
        roomId: room.id,
        eventId: r'$last',
        replyText: null,
      )),
    );
    await network(tester);

    expect(
      jsonDecode(requestsTo('read_markers').single.body),
      containsPair('m.read', r'$last'),
    );
  });

  testWidgets('tapping a chat opens it', (tester) async {
    await pumpRoomList(tester);

    await tester.tap(find.text('Book club'));
    await bounded(tester);

    expect(tester.widget<RoomPage>(find.byType(RoomPage)).room, room);
  });

  testWidgets('the settings button opens Settings', (tester) async {
    await pumpRoomList(tester);

    await tester.tap(find.byTooltip('Settings'));
    await bounded(tester);

    expect(find.byType(SettingsPage), findsOneWidget);
  });

  group('pulling down', () {
    Future<void> pull(WidgetTester tester) async {
      await tester.fling(find.text('Book club'), const Offset(0, 800), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    testWidgets('syncs at once', (tester) async {
      await pumpRoomList(tester);

      await pull(tester);

      expect(client.syncs, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('says so when the sync fails', (tester) async {
      client.syncError = http.ClientException('Failed host lookup');
      await pumpRoomList(tester);

      await pull(tester);

      expect(
        find.text('Could not refresh. Check your connection.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a new room can be created from the keyboard', (tester) async {
    await pumpRoomList(tester);
    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New room'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Chess club');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await network(tester);

    expect(requestsTo('createRoom'), hasLength(1));
  });

  group('communities', () {
    late Room club;

    setUp(() {
      club = buildTestRoom(client, id: '!club:example.org')..partial = false;
      for (final state in [
        StrippedStateEvent(
          type: EventTypes.RoomCreate,
          senderId: '@me:example.org',
          stateKey: '',
          content: {'type': 'm.space'},
        ),
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: '@me:example.org',
          stateKey: '',
          content: {'name': 'Climbing club'},
        ),
      ]) {
        club.setState(state);
      }
      client.rooms.add(club);
    });

    Future<void> openCommunities(WidgetTester tester) async {
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();
    }

    Iterable<Badge> dots(WidgetTester tester) => tester
        .widgetList<Badge>(find.byType(Badge))
        .where((badge) => badge.isLabelVisible);

    testWidgets('chats leave communities out; the Communities tab shows '
        'them', (tester) async {
      await pumpRoomList(tester);

      expect(find.text('Book club'), findsOneWidget);
      expect(find.text('Climbing club'), findsNothing);

      await openCommunities(tester);

      expect(find.text('Communities'), findsNWidgets(2));
      expect(find.text('Climbing club'), findsOneWidget);
      expect(find.text('Book club'), findsNothing);
    });

    testWidgets('back on Communities returns to Chats', (tester) async {
      await pumpRoomList(tester);
      await openCommunities(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsNWidgets(2));
      expect(find.text('Book club'), findsOneWidget);
    });

    testWidgets('a dot marks the tab with something unread', (tester) async {
      await pumpRoomList(tester);

      expect(dots(tester), hasLength(1));
      expect(
        find.ancestor(
          of: find.byIcon(Icons.chat_bubble),
          matching: find.byWidgetPredicate(
            (w) => w is Badge && w.isLabelVisible,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a community opens its page', (tester) async {
      await pumpRoomList(tester);
      await openCommunities(tester);

      await tester.tap(find.text('Climbing club'));
      await bounded(tester);

      expect(
        tester.widget<CommunityPage>(find.byType(CommunityPage)).community,
        club,
      );
    });

    testWidgets('a community offers only leaving', (tester) async {
      await pumpRoomList(tester);
      await openCommunities(tester);

      await tester.longPress(find.text('Climbing club'));
      await tester.pumpAndSettle();

      expect(find.text('Leave community'), findsOneWidget);
      expect(find.text('Mute'), findsNothing);
      expect(find.text('Mark as read'), findsNothing);
    });

    testWidgets('a new community can be created from the Communities + '
        'menu', (tester) async {
      await pumpRoomList(tester);
      await openCommunities(tester);
      await tester.tap(find.byIcon(Icons.add_outlined));
      await tester.pumpAndSettle();

      expect(find.text('New chat'), findsNothing);
      await tester.tap(find.text('New community'));
      await tester.pumpAndSettle();

      expect(find.text('Community name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Rivera family');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await network(tester);

      final create = requestsTo('createRoom').single;
      final body = jsonDecode(create.body) as Map<String, Object?>;
      expect(body['name'], 'Rivera family');
      expect(body['creation_content'], {'type': 'm.space'});
    });
  });

  testWidgets('before the first sync, an empty list shows progress instead of '
      '"No chats yet"', (tester) async {
    client.rooms.clear();
    await pumpRoomList(tester, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No chats yet'), findsNothing);

    await tester.tap(find.text('Communities'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No communities yet'), findsNothing);

    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No communities yet'), findsOneWidget);
  });

  group('onboarding', () {
    testWidgets('opens with the steps not yet shown', (tester) async {
      final container = await pumpRoomList(
        tester,
        onboarding: [OnboardingStep.welcome, OnboardingStep.confirmPeople],
        stored: {
          'onboarding.shown.@me:example.org': [OnboardingStep.welcome.name],
        },
      );

      expect(find.byType(OnboardingFlowPage), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(OnboardingFlowPage))),
        isA<ForwardExitPageRoute>(),
      );
      expect(
        tester
            .widget<OnboardingFlowPage>(find.byType(OnboardingFlowPage))
            .steps,
        [OnboardingStep.confirmPeople],
      );
      expect(container.read(onboardingStoreProvider).flowInProgress, isTrue);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowPage), findsNothing);
      expect(container.read(onboardingStoreProvider).flowInProgress, isFalse);
    });

    testWidgets('a reload still under way opens nothing from the last list', (
      tester,
    ) async {
      final reload = Completer<List<OnboardingStep>>();
      var builds = 0;
      final container = await pumpRoomList(
        tester,
        onboardingBuild: () => builds++ == 0
            ? Future.value(const [OnboardingStep.confirmPeople])
            : reload.future,
      );
      Navigator.of(tester.element(find.byType(OnboardingFlowPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingFlowPage), findsNothing);

      container.invalidate(onboardingStepsProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowPage), findsNothing);
    });

    testWidgets('stays closed when every step was shown', (tester) async {
      await pumpRoomList(
        tester,
        onboarding: [OnboardingStep.welcome],
        stored: {
          'onboarding.shown.@me:example.org': [OnboardingStep.welcome.name],
        },
      );

      expect(find.byType(OnboardingFlowPage), findsNothing);
    });
  });

  group('the recovery offer', () {
    const title = 'Keep your messages if you lose this device';

    testWidgets('asks once, and Not now leaves it', (tester) async {
      final container = await pumpRoomList(
        tester,
        prompt: SecurityPromptDecision.setUpRecovery,
      );

      expect(find.text(title), findsOneWidget);
      expect(
        container.read(securityPromptStoreProvider).lastPrompted(),
        isNotNull,
      );

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.text(title), findsNothing);
      expect(find.byType(SecureBackupPage), findsNothing);
      expect(
        container.read(securityPromptStoreProvider).promptInFlight,
        isFalse,
      );
    });

    testWidgets('Set up recovery opens it', (tester) async {
      await pumpRoomList(tester, prompt: SecurityPromptDecision.setUpRecovery);
      client.withEncryption = true;

      await tester.tap(find.text('Set up recovery'));
      await bounded(tester);

      expect(find.byType(SecureBackupPage), findsOneWidget);
    });

    testWidgets('waits out the cooldown after the last offer', (tester) async {
      await pumpRoomList(
        tester,
        prompt: SecurityPromptDecision.setUpRecovery,
        stored: {
          'security.recovery_prompt_ms': DateTime.now()
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        },
      );

      expect(find.text(title), findsNothing);
    });

    testWidgets('gives way to onboarding that is still to come', (
      tester,
    ) async {
      await pumpRoomList(
        tester,
        prompt: SecurityPromptDecision.setUpRecovery,
        onboarding: [OnboardingStep.welcome],
      );

      expect(find.text(title), findsNothing);
      expect(find.byType(OnboardingFlowPage), findsOneWidget);
    });
  });

  group('a verification request from someone', () {
    testWidgets('can be declined', (tester) async {
      await pumpRoomList(tester);
      final request = FakeKeyVerification();

      verifications.add(request);
      await tester.pumpAndSettle();
      expect(find.text('@bob wants to verify with you.'), findsOneWidget);
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      expect(request.calls, ['rejectVerification']);
      expect(find.byType(VerificationPage), findsNothing);
    });

    testWidgets('once accepted, opens the check', (tester) async {
      await pumpRoomList(tester);
      final request = FakeKeyVerification();

      verifications.add(request);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await bounded(tester);

      expect(request.calls, ['acceptVerification']);
      expect(find.byType(VerificationPage), findsOneWidget);
    });
  });
}
