import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/room_info/presentation/room_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/pump_until.dart';

void main() {
  late List<http.Request> requests;
  late Client client;
  late Room room;
  late FakeImagePicker picker;
  http.Response? Function(http.Request request)? respond;
  Completer<void>? gate;

  setUp(() {
    requests = [];
    respond = null;
    gate = null;
    picker = installFakeImagePicker();
    client = buildTestClient(
      userId: '@me:example.org',
      database: UploadingFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        final custom = respond?.call(request);
        if (custom == null && request.url.pathSegments.contains('media')) {
          return http.Response('', 404);
        }
        requests.add(request);
        await gate?.future;
        return custom ?? http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  void setOwnLevel(int level) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$powerlevels',
      senderId: '@creator:example.org',
      type: EventTypes.RoomPowerLevels,
      stateKey: '',
      content: {
        'users': {'@me:example.org': level},
      },
    ),
  );

  void setJoinRule(String rule) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$join',
      senderId: '@creator:example.org',
      type: EventTypes.RoomJoinRules,
      stateKey: '',
      content: {'join_rule': rule},
    ),
  );

  void setRoomState(String type, Map<String, Object?> content) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$state-' + type,
      senderId: '@creator:example.org',
      type: type,
      stateKey: '',
      content: content,
    ),
  );

  void setDirectChatWith(String userId) =>
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          userId: [room.id],
        },
      );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: RoomSettingsPage(room: room)));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await pumpRealAsync(tester, rounds: 5);
    await tester.pumpAndSettle();
  }

  Future<void> pickAccess(WidgetTester tester, String label) async {
    await tester.tap(find.text('Room access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('an admin makes the room public after confirming', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expect(find.text('Room access'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);

    await pickAccess(tester, 'Public');

    expect(find.text('Make room public?'), findsOneWidget);
    expect(find.textContaining('can find it'), findsOneWidget);
    expect(find.textContaining('join without an invite'), findsOneWidget);
    expect(find.textContaining('read older messages'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(find.text('Make public'));
    await settle(tester);

    expect(requests.map((r) => r.url.pathSegments), [
      contains('directory'),
      contains('m.room.join_rules'),
    ]);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Room access updated'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    await pickAccess(tester, 'Public');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(requests, isEmpty);
    expect(find.text('Make room public?'), findsNothing);
    expect(find.text('Private'), findsOneWidget);
  });

  testWidgets('making a public room private explains what changes', (
    tester,
  ) async {
    setOwnLevel(100);
    setJoinRule('public');
    await pumpPage(tester);

    await pickAccess(tester, 'Private');

    expect(find.text('Make room private?'), findsOneWidget);
    expect(find.textContaining('leaves the public list'), findsOneWidget);
    expect(find.textContaining('need an invite'), findsOneWidget);
    expect(find.textContaining('Nobody is removed'), findsOneWidget);

    await tester.tap(find.text('Make private'));
    await settle(tester);

    expect(requests.map((r) => r.url.pathSegments), [
      contains('m.room.join_rules'),
      contains('directory'),
    ]);
    expect(find.text('Private'), findsOneWidget);
  });

  group('a room inside a community', () {
    void addToCommunity() {
      final community = buildTestRoom(client, id: '!club:example.org')
        ..membership = Membership.join;
      community.setState(
        buildTestEvent(
          community,
          eventId: r'$create',
          senderId: '@creator:example.org',
          type: EventTypes.RoomCreate,
          stateKey: '',
          content: {'type': 'm.space'},
        ),
      );
      community.setState(
        buildTestEvent(
          community,
          eventId: r'$child',
          senderId: '@creator:example.org',
          type: EventTypes.SpaceChild,
          stateKey: room.id,
          content: {
            'via': ['example.org'],
          },
        ),
      );
      client.rooms.add(community);
    }

    Future<List<String?>> accessChoices(WidgetTester tester) async {
      await tester.tap(find.text('Room access'));
      await tester.pumpAndSettle();
      return tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ListTile),
            ),
          )
          .map((tile) => (tile.title! as Text).data)
          .toList();
    }

    testWidgets('offers Community, Ask to join and Private, never Public', (
      tester,
    ) async {
      setOwnLevel(100);
      setJoinRule('restricted');
      addToCommunity();
      await pumpPage(tester);

      expect(await accessChoices(tester), [
        'Community',
        'Ask to join',
        'Private',
      ]);
    });

    testWidgets('a room naming a community it is not listed in cannot be '
        'opened to its members', (tester) async {
      setOwnLevel(100);
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$parent',
          senderId: '@creator:example.org',
          type: EventTypes.SpaceParent,
          stateKey: '!club:example.org',
          content: {
            'via': ['example.org'],
          },
        ),
      );
      await pumpPage(tester);

      expect(await accessChoices(tester), ['Ask to join', 'Private']);
    });

    testWidgets('switching to Ask to join says what changes, then lets '
        'people knock', (tester) async {
      setOwnLevel(100);
      setJoinRule('restricted');
      addToCommunity();
      await pumpPage(tester);

      await pickAccess(tester, 'Ask to join');

      expect(find.text('Let members ask to join?'), findsOneWidget);
      expect(find.textContaining('can ask to join'), findsOneWidget);
      expect(
        find.textContaining('Moderators and admins decide'),
        findsOneWidget,
      );

      await tester.tap(find.text('Let them ask'));
      await settle(tester);

      final joinRule = requests.firstWhere(
        (r) => r.url.pathSegments.contains('m.room.join_rules'),
      );
      expect(jsonDecode(joinRule.body), {'join_rule': 'knock'});
      expect(find.text('Ask to join'), findsOneWidget);
    });

    testWidgets('a room outside any community still offers Public', (
      tester,
    ) async {
      setOwnLevel(100);
      await pumpPage(tester);

      expect(await accessChoices(tester), ['Public', 'Private']);
    });
  });

  testWidgets('a direct chat has no photo or access row', (tester) async {
    setOwnLevel(100);
    setDirectChatWith('@bob:example.org');
    await pumpPage(tester);

    expect(find.text('Room photo'), findsNothing);
    expect(find.text('Room access'), findsNothing);
    expect(find.text('Room name'), findsOneWidget);
  });

  testWidgets('the main address hides the server', (tester) async {
    setOwnLevel(100);
    setRoomState(EventTypes.RoomCanonicalAlias, {
      'alias': '#chess:example.org',
    });
    await pumpPage(tester);

    expect(find.text('#chess'), findsOneWidget);
    expect(find.textContaining('example.org'), findsNothing);

    await tester.tap(find.text('Main address'));
    await tester.pumpAndSettle();

    expect(find.textContaining('example.org'), findsNothing);
  });

  testWidgets('clearing the main address removes it', (tester) async {
    setOwnLevel(100);
    setRoomState(EventTypes.RoomCanonicalAlias, {
      'alias': '#chess:example.org',
    });
    await pumpPage(tester);

    await tester.tap(find.text('Main address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(requests, hasLength(2));
    expect(requests[0].method, 'DELETE');
    expect(requests[0].url.pathSegments.last, '#chess:example.org');
    expect(requests[1].url.pathSegments, contains('m.room.canonical_alias'));
    expect(jsonDecode(requests[1].body), <String, Object?>{});
    expect(find.text('#chess'), findsNothing);
    expect(find.text('#'), findsNothing);
  });

  testWidgets('editors cap name, topic and address lengths', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    for (final (row, limit) in [
      ('Room name', 50),
      ('Topic', 250),
      ('Main address', 50),
    ]) {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x' * (limit + 20));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, limit, reason: row);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the topic row shows at most three lines', (tester) async {
    setOwnLevel(100);
    const topic = 'one\ntwo\nthree\nfour\nfive';
    setRoomState(EventTypes.RoomTopic, {'topic': topic});
    await pumpPage(tester);

    final text = tester.widget<Text>(find.text(topic));
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('removing the photo clears it at once', (tester) async {
    setOwnLevel(100);
    setRoomState(EventTypes.RoomAvatar, {'url': 'mxc://example.org/old'});
    await pumpPage(tester);

    await tester.tap(find.text('Room photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await settle(tester);

    expect(requests, hasLength(1));
    expect(requests.single.url.pathSegments, contains('m.room.avatar'));
    expect(jsonDecode(requests.single.body), <String, Object?>{});
    expect(room.avatar, isNull);
    expect(find.text('Photo updated'), findsOneWidget);
  });

  Iterable<http.Request> writesOf(String type) =>
      requests.where((r) => r.url.pathSegments.contains(type));

  Object? bodyOf(http.Request request) => jsonDecode(request.body);

  http.Response refused() =>
      http.Response('{"errcode":"M_FORBIDDEN","error":"x"}', 403);

  String? subtitleOf(WidgetTester tester, String title) =>
      (tester.widget<ListTile>(find.widgetWithText(ListTile, title)).subtitle
              as Text?)
          ?.data;

  Future<void> edit(WidgetTester tester, String row, String value) async {
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), value);
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  group('the room name', () {
    testWidgets('is saved trimmed and shown at once', (tester) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomName, {'name': 'Chess'});
      await pumpPage(tester);
      expect(subtitleOf(tester, 'Room name'), 'Chess');

      await edit(tester, 'Room name', '  Chess club  ');

      expect(bodyOf(writesOf('m.room.name').single), {'name': 'Chess club'});
      expect(subtitleOf(tester, 'Room name'), 'Chess club');
      expect(find.text('Room name updated'), findsOneWidget);
    });

    testWidgets('Done on the keyboard saves too', (tester) async {
      setOwnLevel(100);
      await pumpPage(tester);
      expect(subtitleOf(tester, 'Room name'), 'Not set');

      await tester.tap(find.text('Room name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Chess club');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(writesOf('m.room.name'), hasLength(1));
    });

    testWidgets('an unchanged name is not sent', (tester) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomName, {'name': 'Chess'});
      await pumpPage(tester);

      await edit(tester, 'Room name', 'Chess');

      expect(requests, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a name after Zuno is refused until it is edited', (
      tester,
    ) async {
      setOwnLevel(100);
      await pumpPage(tester);

      await edit(tester, 'Room name', 'Zun0 support');
      expect(find.textContaining('cannot include Zuno'), findsOneWidget);
      expect(writesOf('m.room.name'), isEmpty);

      await tester.enterText(find.byType(TextField), 'Chess');
      await tester.pump();

      expect(find.textContaining('cannot include Zuno'), findsNothing);
    });

    testWidgets('shows progress while saving and blocks a second edit', (
      tester,
    ) async {
      setOwnLevel(100);
      await pumpPage(tester);
      gate = Completer<void>();

      await tester.tap(find.text('Room name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Chess club');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();

      final row = find.widgetWithText(ListTile, 'Room name');
      expect(
        find.descendant(
          of: row,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(row).onTap, isNull);

      gate!.complete();
      await settle(tester);

      expect(tester.widget<ListTile>(row).onTap, isNotNull);
    });

    testWidgets('a refused rename keeps the old name and says so', (
      tester,
    ) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomName, {'name': 'Chess'});
      respond = (r) => r.url.path.contains('m.room.name') ? refused() : null;
      await pumpPage(tester);

      await edit(tester, 'Room name', 'Chess club');

      expect(find.text('Room name not saved. Try again.'), findsOneWidget);
      expect(subtitleOf(tester, 'Room name'), 'Chess');
    });
  });

  group('the topic', () {
    testWidgets('is saved and shown at once', (tester) async {
      setOwnLevel(100);
      await pumpPage(tester);
      expect(subtitleOf(tester, 'Topic'), 'Not set');

      await edit(tester, 'Topic', 'Weekend hikes');

      expect(
        (bodyOf(writesOf('m.room.topic').single)! as Map)['topic'],
        'Weekend hikes',
      );
      expect(subtitleOf(tester, 'Topic'), 'Weekend hikes');
      expect(find.text('Topic updated'), findsOneWidget);
    });

    testWidgets('an unchanged topic is not sent', (tester) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomTopic, {'topic': 'Weekend hikes'});
      await pumpPage(tester);

      await edit(tester, 'Topic', 'Weekend hikes');

      expect(requests, isEmpty);
    });

    testWidgets('a refused topic says so', (tester) async {
      setOwnLevel(100);
      respond = (r) => r.url.path.contains('m.room.topic') ? refused() : null;
      await pumpPage(tester);

      await edit(tester, 'Topic', 'Weekend hikes');

      expect(find.text('Topic not saved. Try again.'), findsOneWidget);
      expect(subtitleOf(tester, 'Topic'), 'Not set');
    });
  });

  group('the main address', () {
    testWidgets('a new address is registered on this server first', (
      tester,
    ) async {
      setOwnLevel(100);
      respond = (r) => r.url.pathSegments.last == 'aliases'
          ? http.Response(jsonEncode({'aliases': <String>[]}), 200)
          : null;
      await pumpPage(tester);
      expect(subtitleOf(tester, 'Main address'), 'Not set');

      await edit(tester, 'Main address', 'chess');

      expect(requests.map((r) => (r.method, r.url.pathSegments.last)), [
        ('GET', 'aliases'),
        ('PUT', '#chess:example.org'),
        ('PUT', ''),
      ]);
      expect(bodyOf(requests.last), {'alias': '#chess:example.org'});
      expect(subtitleOf(tester, 'Main address'), '#chess');
      expect(find.text('Main address updated'), findsOneWidget);
    });

    testWidgets('an address the server no longer has is still cleared', (
      tester,
    ) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomCanonicalAlias, {
        'alias': '#chess:example.org',
      });
      respond = (r) => r.method == 'DELETE'
          ? http.Response('{"errcode":"M_NOT_FOUND","error":"x"}', 404)
          : null;
      await pumpPage(tester);

      await edit(tester, 'Main address', '');

      expect(writesOf('m.room.canonical_alias'), hasLength(1));
      expect(subtitleOf(tester, 'Main address'), 'Not set');
      expect(find.text('Main address updated'), findsOneWidget);
    });

    testWidgets('a refused removal keeps the address and says so', (
      tester,
    ) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomCanonicalAlias, {
        'alias': '#chess:example.org',
      });
      respond = (r) => r.method == 'DELETE' ? refused() : null;
      await pumpPage(tester);

      await edit(tester, 'Main address', '');

      expect(writesOf('m.room.canonical_alias'), isEmpty);
      expect(subtitleOf(tester, 'Main address'), '#chess');
      expect(find.text('Main address not saved. Try again.'), findsOneWidget);
    });

    testWidgets('an unchanged address is not sent', (tester) async {
      setOwnLevel(100);
      setRoomState(EventTypes.RoomCanonicalAlias, {
        'alias': '#chess:example.org',
      });
      await pumpPage(tester);

      await edit(tester, 'Main address', 'chess');

      expect(requests, isEmpty);
    });
  });

  group('who can read history', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Who can read history'));
      await tester.pumpAndSettle();
    }

    Finder ticked(String label) => find.descendant(
      of: find.widgetWithText(ListTile, label).last,
      matching: find.byIcon(Icons.check_outlined),
    );

    testWidgets('lists every choice with the current one ticked', (
      tester,
    ) async {
      setOwnLevel(100);
      setRoomState(EventTypes.HistoryVisibility, {
        'history_visibility': 'joined',
      });
      await pumpPage(tester);
      expect(
        subtitleOf(tester, 'Who can read history'),
        'Members, from when they joined',
      );

      await openSheet(tester);

      for (final label in [
        'Anyone',
        'Members, including history before they joined',
        'Members, from when they were invited',
      ]) {
        expect(find.text(label), findsOneWidget);
        expect(ticked(label), findsNothing);
      }
      expect(ticked('Members, from when they joined'), findsOneWidget);
    });

    testWidgets('a new choice is saved and shown at once', (tester) async {
      setOwnLevel(100);
      setRoomState(EventTypes.HistoryVisibility, {
        'history_visibility': 'joined',
      });
      await pumpPage(tester);

      await openSheet(tester);
      await tester.tap(find.text('Anyone'));
      await settle(tester);

      expect(bodyOf(writesOf('m.room.history_visibility').single), {
        'history_visibility': 'world_readable',
      });
      expect(subtitleOf(tester, 'Who can read history'), 'Anyone');
      expect(find.text('History setting updated'), findsOneWidget);
    });

    testWidgets('the current choice, or none, sends nothing', (tester) async {
      setOwnLevel(100);
      setRoomState(EventTypes.HistoryVisibility, {
        'history_visibility': 'joined',
      });
      await pumpPage(tester);

      await openSheet(tester);
      await tester.tap(find.text('Members, from when they joined').last);
      await settle(tester);
      await openSheet(tester);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);

      expect(requests, isEmpty);
    });

    testWidgets('a room without the setting shows the Matrix default', (
      tester,
    ) async {
      setOwnLevel(100);
      await pumpPage(tester);

      expect(
        subtitleOf(tester, 'Who can read history'),
        'Members, including history before they joined',
      );
      await openSheet(tester);
      expect(
        ticked('Members, including history before they joined'),
        findsOneWidget,
      );
    });

    testWidgets('a refused change says so', (tester) async {
      setOwnLevel(100);
      respond = (r) =>
          r.url.path.contains('m.room.history_visibility') ? refused() : null;
      await pumpPage(tester);

      await openSheet(tester);
      await tester.tap(find.text('Anyone'));
      await settle(tester);

      expect(
        find.text('History setting not saved. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('the room photo', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Room photo'));
      await tester.pumpAndSettle();
    }

    XFile photo() => XFile.fromData(
      img.encodeJpg(img.Image(width: 800, height: 400)),
      path: 'IMG_0001.jpg',
      mimeType: 'image/jpeg',
    );

    http.Response? uploads(http.Request r) =>
        r.url.pathSegments.last == 'upload'
        ? http.Response(
            jsonEncode({'content_uri': 'mxc://example.org/new'}),
            200,
          )
        : null;

    testWidgets('without a photo there is nothing to remove', (tester) async {
      setOwnLevel(100);
      await pumpPage(tester);
      await openSheet(tester);

      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing);
    });

    testWidgets('a gallery photo is uploaded and set', (tester) async {
      setOwnLevel(100);
      picker.answer = [photo()];
      respond = uploads;
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Choose from gallery'));
      await settle(tester);

      expect(picker.calls, ['image:gallery']);
      expect(requests.first.url.pathSegments.last, 'upload');
      expect(bodyOf(writesOf('m.room.avatar').single), {
        'url': 'mxc://example.org/new',
      });
      expect(room.avatar, Uri.parse('mxc://example.org/new'));
      expect(find.text('Photo updated'), findsOneWidget);
    });

    testWidgets('an abandoned camera shot sends nothing', (tester) async {
      setOwnLevel(100);
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Take photo'));
      await settle(tester);

      expect(picker.calls, ['image:camera']);
      expect(requests, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Room photo'))
            .onTap,
        isNotNull,
      );
    });

    testWidgets('a failed upload says the photo was not saved', (tester) async {
      setOwnLevel(100);
      picker.answer = [photo()];
      respond = (r) => r.url.pathSegments.last == 'upload' ? refused() : null;
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Choose from gallery'));
      await settle(tester);

      expect(writesOf('m.room.avatar'), isEmpty);
      expect(find.text('Photo not saved. Try again.'), findsOneWidget);
    });
  });

  testWidgets('a member sees the settings but cannot open any', (tester) async {
    setOwnLevel(0);
    await pumpPage(tester);

    for (final title in [
      'Room photo',
      'Room name',
      'Topic',
      'Main address',
      'Who can read history',
      'Room access',
    ]) {
      final row = find.widgetWithText(ListTile, title);
      expect(tester.widget<ListTile>(row).onTap, isNull, reason: title);
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.chevron_right_outlined),
        ),
        findsNothing,
        reason: title,
      );
    }
  });
}
