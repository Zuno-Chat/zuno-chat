import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/forwarded_message.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/features/chat/data/discarded_sends.dart';
import 'package:zuno/features/chat/data/forward_uploads.dart';
import 'package:zuno/features/chat/data/room_sender.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/message_contents/voice_message.dart';
import 'package:zuno/features/share/presentation/forward_picker_page.dart';

import '../../../helpers/edited_media.dart';
import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

const _alice = '!alice:example.org';
const _cleo = '!cleo:example.org';

void main() {
  late RoomPageHarness harness;
  late Set<String> refusing;

  setUp(() => refusing = {});

  Event photo(
    String id, {
    String sender = '@bob:example.org',
    EventStatus status = EventStatus.synced,
    int? index,
  }) => buildTestEvent(
    harness.room,
    eventId: id,
    senderId: sender,
    originServerTs: DateTime(2026, 9, 20, 12),
    status: status,
    content: {
      'msgtype': 'm.image',
      'body': '$id.jpg',
      'url': 'mxc://example.org/$id',
      'info': {'w': 40, 'h': 30, 'mimetype': 'image/jpeg'},
      if (index != null)
        ...galleryGroupContent(id: 'g', index: index, count: 3),
    },
  );

  Future<void> openRoom(
    WidgetTester tester,
    List<Event> Function() events, {
    bool encrypting = false,
    List<Override> overrides = const [],
  }) async {
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      encrypting: encrypting,
      overrides: overrides,
    );
    harness.respond = (request) {
      final segments = request.url.pathSegments;
      if (segments.contains('send') && refusing.any(segments.contains)) {
        return http.Response(
          jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'no'}),
          400,
        );
      }
      if (request.url.path.contains('/download/')) {
        return http.Response(
          jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
          404,
        );
      }
      return null;
    };
    harness
      ..addChat(_alice, 'Alice')
      ..addChat(_cleo, 'Cleo');
    harness.db.events = events();
    await harness.pumpRoomPage(tester);
  }

  Future<void> forwardTo(
    WidgetTester tester,
    Finder message,
    String action,
    List<String> chats,
  ) async {
    await tester.longPress(message);
    await harness.settle(tester);
    await tester.tap(find.widgetWithText(ListTile, action));
    await harness.settle(tester);
    await harness.forwardToChats(tester, chats);
  }

  testWidgets(
    'forwarding a photo to two chats sends one copy to each and says Sent to 2 chats',
    (tester) async {
      await openRoom(tester, () => [photo('p1')]);

      await forwardTo(tester, find.byType(ImageMessage), 'Forward', [
        'Alice',
        'Cleo',
      ]);

      for (final chat in [_alice, _cleo]) {
        final copy = harness.sentTo(chat).single;
        expect(copy['url'], 'mxc://example.org/p1');
        expect(copy[forwardedKey], isTrue);
      }
      expect(find.byType(ForwardPickerPage), findsNothing);
      expect(find.text('Sent to 2 chats.'), findsOneWidget);
    },
  );

  testWidgets('a gallery with an unsent item forwards the sent ones', (
    tester,
  ) async {
    await openRoom(
      tester,
      () => [
        photo(
          'txn-3',
          sender: '@me:example.org',
          status: EventStatus.error,
          index: 2,
        ),
        photo(r'$p2', sender: '@me:example.org', index: 1),
        photo(r'$p1', sender: '@me:example.org', index: 0),
      ],
    );

    await forwardTo(tester, find.byType(GalleryMessage), 'Forward all (2)', [
      'Alice',
    ]);

    final copies = harness.sentTo(_alice);
    expect(copies.map((c) => c['url']), [
      r'mxc://example.org/$p1',
      r'mxc://example.org/$p2',
    ]);
    final groups = [for (final c in copies) c[galleryGroupKey] as Map];
    expect(groups.map((g) => g['index']), [0, 1]);
    expect(groups.map((g) => g['count']), [2, 2]);
    expect(groups.map((g) => g['id']).toSet(), hasLength(1));
    expect(groups.first['id'], isNot('g'));
    expect(find.text('Sent to 1 chat.'), findsOneWidget);
  });

  testWidgets('a failed chat is named', (tester) async {
    refusing.add(_cleo);
    await openRoom(tester, () => [photo('p1')]);

    await forwardTo(tester, find.byType(ImageMessage), 'Forward', [
      'Alice',
      'Cleo',
    ]);

    expect(harness.sentTo(_alice), hasLength(1));
    expect(find.text('Could not send to Cleo. Try again.'), findsOneWidget);
  });

  testWidgets('two failed chats are counted', (tester) async {
    refusing.addAll([_alice, _cleo]);
    await openRoom(tester, () => [photo('p1')]);

    await forwardTo(tester, find.byType(ImageMessage), 'Forward', [
      'Alice',
      'Cleo',
    ]);

    expect(find.text('Could not send to 2 chats. Try again.'), findsOneWidget);
  });

  testWidgets('a chat that cannot be reached offline says to check the '
      'connection', (tester) async {
    await openRoom(
      tester,
      () => [photo('p1')],
      overrides: [
        roomSenderProvider.overrideWith(
          (ref, room) =>
              _OfflineSender(room, ref.watch(discardedSendsProvider)),
        ),
      ],
    );

    await forwardTo(tester, find.byType(ImageMessage), 'Forward', ['Alice']);

    expect(
      find.text(
        'Could not send to Alice. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an edited caption goes out as edited', (tester) async {
    await openRoom(tester, () => editedPhoto(harness.room));

    await forwardTo(tester, find.byType(ImageMessage), 'Forward', ['Alice']);

    expect(harness.sentTo(_alice).single['body'], 'New caption');
  });

  testWidgets('a voice message offers no Forward', (tester) async {
    await openRoom(
      tester,
      () => [
        buildTestEvent(
          harness.room,
          eventId: r'$v1',
          senderId: '@bob:example.org',
          originServerTs: DateTime(2026, 9, 20, 12),
          status: EventStatus.synced,
          content: {
            'msgtype': 'm.audio',
            'body': 'Voice message',
            'url': 'mxc://example.org/v1',
            'info': {'duration': 3000, 'mimetype': 'audio/ogg'},
            'org.matrix.msc3245.voice': <String, Object?>{},
          },
        ),
      ],
    );

    await tester.longPress(find.byType(VoiceMessage));
    await harness.settle(tester);

    expect(find.widgetWithText(ListTile, 'Share'), findsOneWidget);
    expect(find.textContaining('Forward'), findsNothing);
  });

  testWidgets(
    'from an encrypted chat the picker warns about an unencrypted one',
    (tester) async {
      await openRoom(tester, () => [photo('p1')], encrypting: true);
      encryptRoom(harness.room);

      await tester.longPress(find.byType(ImageMessage));
      await harness.settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Forward'));
      await harness.settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ForwardPickerPage),
          matching: find.text('Alice'),
        ),
      );
      await tester.pump();

      expect(find.text('This chat is not encrypted.'), findsOneWidget);
    },
  );
}

class _OfflineSender extends RoomSender {
  _OfflineSender(Room room, DiscardedSends discarded)
    : super(
        room: room,
        discarded: discarded,
        reduceMediaSize: () => false,
        chatOpen: () => false,
        say: (_) {},
      );

  @override
  Future<Object?> forward(List<Event> items, {ForwardUploads? uploads}) async =>
      http.ClientException('offline');
}
