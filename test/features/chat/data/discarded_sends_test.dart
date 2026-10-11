import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/features/chat/data/discarded_sends.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late SharedPreferences prefs;
  late Room room;

  Room roomOf(String userId, {String id = '!room:example.org'}) =>
      buildTestRoom(buildTestClient(userId: userId), id: id);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    room = roomOf('@me:example.org');
  });

  Event unsent(
    String txid, {
    EventStatus status = EventStatus.error,
    String sender = '@me:example.org',
    String? galleryId,
  }) => buildTestEvent(
    room,
    eventId: txid,
    senderId: sender,
    status: status,
    content: {
      'msgtype': MessageTypes.Image,
      'body': 'photo.jpg',
      if (galleryId != null)
        ...galleryGroupContent(id: galleryId, index: 0, count: 2),
    },
  );

  test('a discarded send is still known after a restart', () async {
    await DiscardedSends(prefs).add(room, 'txn-1');

    final restarted = DiscardedSends(prefs);

    expect(restarted.contains(room, ['txn-1']), isTrue);
    expect(restarted.contains(room, ['txn-2', null]), isFalse);
  });

  test('a send counts as discarded when its gallery is', () async {
    final discarded = DiscardedSends(prefs);
    await discarded.add(room, 'gallery-1');

    expect(discarded.contains(room, ['txn-1', 'gallery-1']), isTrue);
  });

  test(
    "another account on the device does not see this one's record",
    () async {
      await DiscardedSends(prefs).add(room, 'txn-1');

      final other = roomOf('@other:example.org');

      expect(DiscardedSends(prefs).contains(other, ['txn-1']), isFalse);
    },
  );

  test('a handled send is removed, and an empty record leaves nothing '
      'stored', () async {
    final discarded = DiscardedSends(prefs);
    await discarded.add(room, 'txn-1');

    await discarded.remove(room, 'txn-1');

    expect(discarded.contains(room, ['txn-1']), isFalse);
    expect(prefs.getKeys(), isEmpty);
  });

  group('prune', () {
    test('drops what matches nothing unsent in the room, and keeps what does '
        'and what other rooms hold', () async {
      final discarded = DiscardedSends(prefs);
      final elsewhere = roomOf('@me:example.org', id: '!other:example.org');
      for (final id in ['txn-gone', 'txn-left', 'gallery-gone', 'gallery-1']) {
        await discarded.add(room, id);
      }
      await discarded.add(elsewhere, 'txn-elsewhere');

      await discarded.prune(room, [
        unsent('txn-left'),
        unsent('txn-2', status: EventStatus.sending, galleryId: 'gallery-1'),
        unsent(
          'txn-sent',
          status: EventStatus.synced,
          galleryId: 'gallery-gone',
        ),
      ]);

      expect(discarded.contains(room, ['txn-gone']), isFalse);
      expect(discarded.contains(room, ['gallery-gone']), isFalse);
      expect(discarded.contains(room, ['txn-left']), isTrue);
      expect(discarded.contains(room, ['gallery-1']), isTrue);
      expect(discarded.contains(elsewhere, ['txn-elsewhere']), isTrue);
    });

    test('keeps what this device is still sending', () async {
      final discarded = DiscardedSends(prefs);
      await discarded.add(room, 'txn-1');
      await discarded.add(room, 'gallery-1');
      final upload = Completer<void>();

      final sending = discarded.whileSending([
        'txn-1',
        'gallery-1',
      ], () => upload.future);
      await discarded.prune(room, const []);

      expect(discarded.isSending('txn-1'), isTrue);
      expect(discarded.contains(room, ['txn-1']), isTrue);
      expect(discarded.contains(room, ['gallery-1']), isTrue);

      upload.complete();
      await sending;
      await discarded.prune(room, const []);

      expect(discarded.isSending('txn-1'), isFalse);
      expect(prefs.getKeys(), isEmpty);
    });

    test("ignores someone else's unsent events", () async {
      final discarded = DiscardedSends(prefs);
      await discarded.add(room, 'txn-1');

      await discarded.prune(room, [
        unsent('txn-1', sender: '@bob:example.org'),
      ]);

      expect(discarded.contains(room, ['txn-1']), isFalse);
    });
  });

  test('an unreadable record is reported and read as empty', () async {
    SharedPreferences.setMockInitialValues({
      'chat.discarded_sends.@me:example.org': 'not json',
    });
    prefs = await SharedPreferences.getInstance();

    late bool found;
    final reports = await reportsDuring(
      () async => found = DiscardedSends(prefs).contains(room, ['txn-1']),
    );

    expect(found, isFalse);
    expect(reports, ['discarded sends read']);
  });
}
