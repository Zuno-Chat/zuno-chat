import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/blocking/presentation/block_person.dart';
import 'package:zuno/features/communities/presentation/community_page.dart';
import 'package:zuno/features/rooms/presentation/room_invite_page.dart';

import '../../../helpers/fake_matrix.dart';

class _ForgettingDatabase extends FakeDatabaseApi {
  @override
  Future<void> forgetRoom(String roomId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late bool refuseReports;
  late bool refuseJoins;
  late bool offline;
  late Client client;
  late Room room;

  setUp(() {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(notificationsChannel, null),
    );
    requests = [];
    refuseReports = false;
    refuseJoins = false;
    offline = false;
    client = buildTestClient(
      userId: '@me:example.org',
      database: _ForgettingDatabase(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (offline) {
          throw http.ClientException('Failed host lookup', request.url);
        }
        if (refuseJoins && request.url.path.endsWith('/join')) {
          return http.Response(
            jsonEncode({
              'errcode': 'M_FORBIDDEN',
              'error': 'You are not invited to this room.',
            }),
            403,
          );
        }
        if (refuseReports && request.url.path.endsWith('/report')) {
          return http.Response(
            jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Slow down'}),
            429,
          );
        }
        if (request.url.path.endsWith('/join')) {
          return http.Response(jsonEncode({'room_id': room.id}), 200);
        }
        return http.Response('{}', 200);
      }),
    )..homeserver = Uri.parse('https://example.org');
    client.bearerToken = 'token';
    room = buildTestRoom(client)..membership = Membership.invite;
    client.rooms.add(room);
  });

  void setMember(String userId, String membership, {required String sender}) {
    room.setState(
      buildTestEvent(
        room,
        eventId: '\$member-$userId',
        senderId: sender,
        type: EventTypes.RoomMember,
        stateKey: userId,
        content: {'membership': membership, 'displayname': userId},
      ),
    );
  }

  void inviteFromBob() {
    setMember('@bob:example.org', 'join', sender: '@bob:example.org');
    setMember('@me:example.org', 'invite', sender: '@bob:example.org');
  }

  Future<void> settleNetwork(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<void> openInvite(
    WidgetTester tester, {
    BlockPerson? blockPerson,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RoomInvitePage(room: room, blockPerson: blockPerson),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleNetwork(tester);
  }

  Iterable<String> requestedPaths() => requests.map((r) => r.url.path);

  final sheetSendButton = find.widgetWithText(
    FilledButton,
    'Report and decline',
  );

  testWidgets('a community invitation says so, and joining opens the '
      'community', (tester) async {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$create',
        senderId: '@bob:example.org',
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': 'm.space'},
      ),
    );
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$name',
        senderId: '@bob:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Climbing club'},
      ),
    );
    inviteFromBob();
    await openInvite(tester);

    expect(find.text('Climbing club'), findsOneWidget);
    expect(
      find.textContaining('invited you to this community.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(requestedPaths().any((p) => p.endsWith('/join')), isTrue);
    expect(find.byType(CommunityPage), findsOneWidget);
  });

  testWidgets('reports the inviter, then declines', (tester) async {
    inviteFromBob();
    await openInvite(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Report and decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(sheetSendButton);
    await settleNetwork(tester);

    final report = requests.firstWhere((r) => r.url.path.endsWith('/report'));
    expect(
      report.url.path,
      '/_matrix/client/v3/users/${Uri.encodeComponent('@bob:example.org')}'
      '/report',
    );
    expect(jsonDecode(report.body), {'reason': 'spam (room ${room.id})'});
    expect(requestedPaths().where((p) => p.endsWith('/leave')), hasLength(1));
    expect(find.byType(RoomInvitePage), findsNothing);
  });

  testWidgets('a refused report leaves the invitation alone', (tester) async {
    inviteFromBob();
    refuseReports = true;
    await openInvite(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Report and decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(sheetSendButton);
    await settleNetwork(tester);

    expect(find.text('The report was not sent. Try again.'), findsOneWidget);
    expect(requestedPaths().where((p) => p.endsWith('/leave')), isEmpty);
    expect(find.byType(RoomInvitePage), findsOneWidget);
  });

  testWidgets('closing the sheet neither reports nor declines', (tester) async {
    inviteFromBob();
    await openInvite(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Report and decline'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await settleNetwork(tester);

    expect(requestedPaths().where((p) => p.endsWith('/report')), isEmpty);
    expect(requestedPaths().where((p) => p.endsWith('/leave')), isEmpty);
    expect(find.byType(RoomInvitePage), findsOneWidget);
  });

  testWidgets('an invitation from nobody known cannot be reported', (
    tester,
  ) async {
    await openInvite(tester);

    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Report and decline'), findsNothing);
    expect(find.text('Block and decline'), findsNothing);
  });

  testWidgets('blocks the inviter, which declines, and leaves the page', (
    tester,
  ) async {
    inviteFromBob();
    final blocked = <String>[];
    await openInvite(tester, blockPerson: (id) async => blocked.add(id));

    await tester.tap(find.widgetWithText(TextButton, 'Block and decline'));
    await tester.pumpAndSettle();
    expect(find.text('Block @bob:example.org?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await settleNetwork(tester);

    expect(blocked, ['@bob:example.org']);
    expect(find.byType(RoomInvitePage), findsNothing);
  });

  testWidgets('backing out of the block keeps the invitation open', (
    tester,
  ) async {
    inviteFromBob();
    final blocked = <String>[];
    await openInvite(tester, blockPerson: (id) async => blocked.add(id));

    await tester.tap(find.widgetWithText(TextButton, 'Block and decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settleNetwork(tester);

    expect(blocked, isEmpty);
    expect(requestedPaths().where((p) => p.endsWith('/leave')), isEmpty);
    expect(find.byType(RoomInvitePage), findsOneWidget);
  });

  testWidgets('a refused join says so, without the server error', (
    tester,
  ) async {
    inviteFromBob();
    refuseJoins = true;
    await openInvite(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await settleNetwork(tester);

    expect(find.text('Could not join.'), findsOneWidget);
    expect(find.textContaining('M_FORBIDDEN'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byType(RoomInvitePage), findsOneWidget);
  });

  testWidgets('declining while offline says to check the connection', (
    tester,
  ) async {
    inviteFromBob();
    await openInvite(tester);
    offline = true;

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await settleNetwork(tester);

    expect(
      find.text('Could not decline. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byType(RoomInvitePage), findsOneWidget);
  });

  testWidgets('a refused block leaves the invitation alone', (tester) async {
    inviteFromBob();
    await openInvite(
      tester,
      blockPerson: (_) async => throw Exception('offline'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Block and decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await settleNetwork(tester);

    expect(find.text('Not blocked. Try again.'), findsOneWidget);
    expect(find.byType(RoomInvitePage), findsOneWidget);
  });
}
