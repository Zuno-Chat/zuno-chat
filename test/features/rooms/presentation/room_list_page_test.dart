import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/notifications/messages/message_notification_provider.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/security/security_prompt.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/communities/presentation/community_page.dart';
import 'package:zuno/features/onboarding/presentation/onboarding_flow_page.dart';
import 'package:zuno/features/rooms/presentation/chat_row.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';
import 'package:zuno/features/settings/presentation/settings_page.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/room_list_page_harness.dart';
import '../../../helpers/room_opening_channels.dart';

class _StubClient extends Client {
  _StubClient({required super.httpClient})
    : super('test', database: TimelineCapableFakeDatabaseApi());

  bool withEncryption = false;

  late final Encryption _encryption = Encryption(client: this);

  @override
  Encryption? get encryption => withEncryption ? _encryption : null;
}

void main() {
  late _StubClient client;
  late Room room;
  late List<http.Request> requests;
  late bool offline;

  setUp(() {
    installRoomOpeningChannels();
    requests = [];
    offline = false;
    client = _StubClient(
      httpClient: FakeHttpClient((request) async {
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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = await pumpRoomListPage(
      tester,
      client,
      stored: stored,
      overrides: [
        onboardingStepsProvider.overrideWith(
          (ref) => onboardingBuild?.call() ?? Future.value(onboarding),
        ),
        securityPromptProvider.overrideWith((ref) async => prompt),
      ],
    );
    await tester.pump();
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
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

  void mute({bool muted = true}) {
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            if (muted)
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

  void serverSaysMuted(bool muted) {
    mute(muted: muted);
    client.onSync.add(
      SyncUpdate(
        nextBatch: 's-push-rules',
        accountData: [client.accountData['m.push_rules']!],
      ),
    );
  }

  Finder mutedMark() => find.descendant(
    of: find.byType(ChatRow),
    matching: find.byIcon(Icons.notifications_off_outlined),
  );

  group('the actions on a chat', () {
    testWidgets('an unread chat can be marked read', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      expect(find.text('Mark as read'), findsOneWidget);
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

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

      expect(mutedMark(), findsNothing);
      await tester.tap(find.text('Mute'));
      await tester.pumpAndSettle();

      final rule = requestsTo('pushrules').single;
      expect(rule.method, 'PUT');
      expect(rule.url.pathSegments, contains('override'));
      expect(mutedMark(), findsOneWidget);

      serverSaysMuted(true);
      await tester.pumpAndSettle();
      expect(mutedMark(), findsOneWidget);
    });

    testWidgets('a muted chat offers Unmute instead', (tester) async {
      mute();
      await pumpRoomList(tester);
      await openActions(tester);

      expect(find.text('Mute'), findsNothing);
      await tester.tap(find.text('Unmute'));
      await tester.pumpAndSettle();

      expect(requestsTo('pushrules').single.method, 'DELETE');
      expect(mutedMark(), findsNothing);

      serverSaysMuted(false);
      await tester.pumpAndSettle();
    });

    testWidgets('leaving asks first', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      expect(find.text('Leave room?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(requestsTo('leave'), hasLength(1));
    });

    testWidgets('closing the sheet does nothing', (tester) async {
      await pumpRoomList(tester);
      await openActions(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(requests, isEmpty);
    });

    testWidgets('muting offline says what failed, not the error', (
      tester,
    ) async {
      await pumpRoomList(tester);
      await openActions(tester);
      offline = true;

      await tester.tap(find.text('Mute'));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();
      expect(
        find.text('Not unmuted. Check your connection and try again.'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(tester.element(find.byType(RoomListPage)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await openActions(tester);
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();
      expect(
        find.text('Not marked as read. Check your connection and try again.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('starts none of the app-wide services, which the app runs '
      'itself', (tester) async {
    final container = await pumpRoomList(tester);

    expect(container.exists(messageNotificationProvider), isFalse);
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

  testWidgets('a new room can be created from the keyboard', (tester) async {
    await pumpRoomList(tester);
    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New room'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Chess club');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

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
      await tester.tap(find.bySemanticsLabel('Communities'));
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
      await tester.pumpAndSettle();

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

    await tester.tap(find.bySemanticsLabel('Communities'));
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
    Future<List<OnboardingStep>> Function() inTurn(
      List<Future<List<OnboardingStep>>> lists,
    ) {
      var builds = 0;
      return () => lists[builds++];
    }

    Future<void> finishFlow(WidgetTester tester) async {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingFlowPage), findsNothing);
    }

    testWidgets('opens with the steps decided for this sign-in', (
      tester,
    ) async {
      final container = await pumpRoomList(
        tester,
        onboarding: [OnboardingStep.privacy],
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
        [OnboardingStep.privacy],
      );
      expect(container.read(onboardingStoreProvider).flow, OnboardingFlow.open);

      await finishFlow(tester);

      expect(container.read(onboardingStoreProvider).flow, OnboardingFlow.done);
    });

    testWidgets('stays closed when there is nothing to ask', (tester) async {
      final container = await pumpRoomList(tester);

      expect(find.byType(OnboardingFlowPage), findsNothing);
      expect(container.read(onboardingStoreProvider).flow, OnboardingFlow.done);
    });

    testWidgets('a list that changes after the flow, as a new delivery mode '
        'makes it, does not reopen the flow over Settings', (tester) async {
      final container = await pumpRoomList(
        tester,
        onboardingBuild: inTurn([
          Future.value(const [OnboardingStep.privacy]),
          Future.value(const [OnboardingStep.batteryExemption]),
        ]),
      );
      await finishFlow(tester);
      Navigator.of(tester.element(find.byType(RoomListPage))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Delivery')),
        ),
      );
      await tester.pumpAndSettle();

      container.invalidate(onboardingStepsProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowPage), findsNothing);
      expect(find.text('Delivery'), findsOneWidget);
    });

    testWidgets('a sign-in that had nothing to ask stays that way', (
      tester,
    ) async {
      final container = await pumpRoomList(
        tester,
        onboardingBuild: inTurn([
          Future.value(const []),
          Future.value(const [OnboardingStep.batteryExemption]),
        ]),
      );

      container.invalidate(onboardingStepsProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowPage), findsNothing);
    });

    testWidgets('a new sign-in gets its own flow, from its own list', (
      tester,
    ) async {
      final nextList = Completer<List<OnboardingStep>>();
      final container = await pumpRoomList(
        tester,
        onboardingBuild: inTurn([
          Future.value(const [OnboardingStep.privacy]),
          nextList.future,
        ]),
      );
      await finishFlow(tester);

      client.onLoginStateChanged.add(LoginState.loggedOut);
      await tester.pump();
      client.onLoginStateChanged.add(LoginState.loggedIn);
      await tester.pump();
      container.invalidate(onboardingStepsProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowPage), findsNothing);
      expect(
        container.read(onboardingStoreProvider).flow,
        OnboardingFlow.undecided,
      );

      nextList.complete(const [OnboardingStep.welcome]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<OnboardingFlowPage>(find.byType(OnboardingFlowPage))
            .steps,
        [OnboardingStep.welcome],
      );
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
          'security.recovery_prompt_ms': clock
              .now()
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

    testWidgets('goes ahead once the flow has run, even with steps still '
        'listed', (tester) async {
      final container = await pumpRoomList(
        tester,
        prompt: SecurityPromptDecision.setUpRecovery,
        onboarding: [OnboardingStep.privacy],
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);

      container.invalidate(securityPromptProvider);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
    });
  });
}
