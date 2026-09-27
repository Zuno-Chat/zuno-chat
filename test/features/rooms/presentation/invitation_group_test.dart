import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/mxc_avatar.dart';
import 'package:zuno/features/rooms/presentation/invitation_group.dart';
import 'package:zuno/features/rooms/presentation/room_invite_page.dart';

import '../../../helpers/fake_matrix.dart';

class _ForgettingDatabaseApi extends TimelineCapableFakeDatabaseApi {
  @override
  Future<void> forgetRoom(String roomId) async {}
}

void main() {
  late Client client;
  late List<http.Request> requests;
  late List<String> notificationCalls;
  late bool offline;
  Completer<void>? gate;

  setUp(() {
    requests = [];
    notificationCalls = [];
    offline = false;
    gate = null;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      notificationCalls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    client = Client(
      'test',
      database: _ForgettingDatabaseApi(),
      httpClient: MockClient((request) async {
        requests.add(request);
        await gate?.future;
        if (offline) {
          throw http.ClientException('Failed host lookup', request.url);
        }
        return http.Response('{"room_id":"!room:example.org"}', 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
  });

  Room invitation({String? name, bool direct = false, String? inviter}) {
    final room = buildTestRoom(client)
      ..membership = Membership.invite
      ..partial = false;
    if (inviter != null) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          senderId: inviter,
          stateKey: '@me:example.org',
          content: {
            'membership': 'invite',
            'is_direct': ?(direct ? true : null),
          },
        ),
      );
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          senderId: inviter,
          stateKey: inviter,
          content: {'membership': 'join', 'displayname': 'Bob'},
        ),
      );
    }
    if (name != null) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: inviter ?? '@x:example.org',
          stateKey: '',
          content: {'name': name},
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  Future<void> pumpGroup(WidgetTester tester, List<Room> rooms) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InvitationGroup(invitations: rooms)),
      ),
    );
    await tester.pump();
  }

  Future<void> network(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Iterable<String> calls() => requests.map((r) => r.url.pathSegments.last);

  testWidgets('a chat invitation is named after the person', (tester) async {
    await pumpGroup(tester, [
      invitation(direct: true, inviter: '@bob:example.org'),
    ]);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Invited you to chat'), findsOneWidget);
    expect(
      tester.widget<MxcAvatar>(find.byType(MxcAvatar)).toneSeed,
      '@bob:example.org',
    );
  });

  testWidgets('a room invitation is named after the room and says who sent '
      'it', (tester) async {
    final room = invitation(name: 'Book club', inviter: '@bob:example.org');
    await pumpGroup(tester, [room]);

    expect(find.text('Book club'), findsOneWidget);
    expect(find.text('Bob invited you'), findsOneWidget);
    expect(tester.widget<MxcAvatar>(find.byType(MxcAvatar)).toneSeed, room.id);
  });

  testWidgets('an invitation from nobody known says Someone', (tester) async {
    await pumpGroup(tester, [invitation()]);
    expect(find.text('Someone'), findsOneWidget);

    await pumpGroup(tester, [invitation(name: 'Book club')]);
    expect(find.text('Someone invited you'), findsOneWidget);
  });

  testWidgets('tapping it opens the invitation', (tester) async {
    await pumpGroup(tester, [invitation(inviter: '@bob:example.org')]);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.byType(RoomInvitePage), findsOneWidget);
  });

  testWidgets('Join joins and clears the notification', (tester) async {
    await pumpGroup(tester, [
      invitation(name: 'Book club', inviter: '@bob:example.org'),
    ]);

    await tester.tap(find.text('Join'));
    await network(tester);

    expect(calls(), ['join']);
    expect(notificationCalls, contains('cancel'));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Decline leaves, and forgets a chat', (tester) async {
    await pumpGroup(tester, [
      invitation(direct: true, inviter: '@bob:example.org'),
    ]);

    await tester.tap(find.text('Decline'));
    await network(tester);

    expect(calls(), ['leave', 'forget']);
    expect(notificationCalls, contains('cancel'));
  });

  testWidgets('both answers wait while one is on its way', (tester) async {
    await pumpGroup(tester, [invitation(inviter: '@bob:example.org')]);
    gate = Completer<void>();

    await tester.tap(find.text('Join'));
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Decline'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Join'))
          .onPressed,
      isNull,
    );

    gate!.complete();
    await network(tester);

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Join'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('joining offline says what failed, not the error', (
    tester,
  ) async {
    await pumpGroup(tester, [
      invitation(name: 'Book club', inviter: '@bob:example.org'),
    ]);
    offline = true;

    await tester.tap(find.text('Join'));
    await network(tester);

    expect(
      find.text('Could not join. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('declining offline says what failed, not the error', (
    tester,
  ) async {
    await pumpGroup(tester, [invitation(inviter: '@bob:example.org')]);
    offline = true;

    await tester.tap(find.text('Decline'));
    await network(tester);

    expect(
      find.text('Could not decline. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
  });
}
