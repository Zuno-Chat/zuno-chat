import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/files/file_system.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/notifications/messages/notification_ids.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';

StoredNotificationLine _line(String eventId) => StoredNotificationLine(
  eventId: eventId,
  senderId: '@a:x',
  timestamp: DateTime.utc(2031, 1, 1, 12),
);

StoredNotificationThread _thread(
  String roomId,
  List<StoredNotificationLine> lines,
) => StoredNotificationThread(roomId: roomId, isGroupChat: false, lines: lines);

Future<Set<int>?> Function() _showing(Iterable<String> rooms) =>
    () async => {for (final room in rooms) messageNotificationIdFor(room)};

Future<Set<int>?> _showingNone() async => {};

void main() {
  late Directory dir;
  late NotificationThreadStore store;

  File storeFile() => dir.childFile(notificationThreadsFileName);

  NotificationThreadStore storeIn() =>
      NotificationThreadStore(directory: () async => dir);

  setUp(() async {
    dir = await fileSystem.systemTempDirectory.createTemp('threads');
    addTearDown(() => dir.delete(recursive: true));
    store = storeIn();
  });

  test('round-trips the bookkeeping of every line and the preview it was '
      'shown at, and keeps no text, names or pictures', () async {
    final stored = StoredNotificationLine(
      eventId: r'$2',
      senderId: '@b:x',
      kind: NotificationLineKind.notice,
      timestamp: DateTime.utc(2031, 1, 1, 13),
      placeholder: true,
      imageUri: 'content://zuno/1',
      imageMimeType: 'image/jpeg',
      quiet: true,
    );
    final shown = NotificationThread(
      roomId: '!r:x',
      title: 'Family',
      isGroupChat: true,
      lines: [
        _line(r'$1').rendered(senderName: 'Alice', text: 'secret plans'),
        stored.rendered(
          senderName: 'Bob',
          senderAvatarUrl: Uri.parse('mxc://x/bob'),
          text: 'a cat',
        ),
      ],
    );
    await store.write(
      shown.storedAt(NotificationPreview.full),
      showing: _showingNone,
    );

    final file = await storeFile().readAsString();
    for (final secret in ['secret', 'a cat', 'Alice', 'Bob', 'Family', 'mxc']) {
      expect(file, isNot(contains(secret)), reason: secret);
    }
    final thread = (await storeIn().read('!r:x'))!;
    expect(thread.isGroupChat, isTrue);
    expect(thread.preview, NotificationPreview.full);
    final first = thread.lines.first;
    expect(first.eventId, r'$1');
    expect(first.senderId, '@a:x');
    expect(first.kind, NotificationLineKind.message);
    expect(first.timestamp, DateTime.utc(2031, 1, 1, 12));
    expect(first.placeholder, isFalse);
    expect(first.quiet, isFalse);
    final line = thread.lines.last;
    expect(line.eventId, r'$2');
    expect(line.senderId, '@b:x');
    expect(line.kind, NotificationLineKind.notice);
    expect(line.placeholder, isTrue);
    expect(line.imageUri, 'content://zuno/1');
    expect(line.imageMimeType, 'image/jpeg');
    expect(line.quiet, isTrue);
  });

  test('a thread stored without its room reads as nothing', () async {
    await storeFile().writeAsString(
      '{"!r:x":{"lines":[{"senderId":"@a:x","kind":"message","ts":0}]}}',
    );

    expect(await store.read('!r:x'), isNull);
  });

  test('a line of a kind this build does not know reads as a message, so a '
      'lower preview level hides its text', () async {
    await storeFile().writeAsString(
      '{"!r:x":{"roomId":"!r:x","lines":'
      '[{"senderId":"@a:x","kind":"retired","ts":0}]}}',
    );

    final thread = (await store.read('!r:x'))!;
    expect(thread.preview, isNull);
    final line = thread.lines.single;
    expect(line.kind, NotificationLineKind.message);
    expect(line.placeholder, isFalse);
    expect(line.quiet, isFalse);
  });

  test('is empty for a room never posted', () async {
    expect(await store.read('!nope:x'), isNull);
  });

  test('reads nothing once its file is gone, as after the badge push or the '
      'sign-out wipe', () async {
    await store.write(_thread('!r:x', [_line(r'$1')]), showing: _showingNone);

    await storeFile().delete();

    expect(await store.read('!r:x'), isNull);
  });

  test('keeps only the newest lines', () async {
    await store.write(
      _thread('!r:x', [
        for (var i = 0; i < maxNotificationLines + 3; i++) _line('\$$i'),
      ]),
      showing: _showingNone,
    );

    final stored = (await store.read('!r:x'))!;
    expect(stored.lines, hasLength(maxNotificationLines));
    expect(stored.lines.last.eventId, '\$${maxNotificationLines + 2}');
  });

  test('drops every other thread whose notification no longer shows when it '
      'writes', () async {
    await store.write(_thread('!a:x', [_line(r'$a')]), showing: _showingNone);
    await store.write(
      _thread('!b:x', [_line(r'$b')]),
      showing: _showing(['!a:x']),
    );

    await store.write(
      _thread('!c:x', [_line(r'$c')]),
      showing: _showing(['!a:x', '!c:x']),
    );

    expect(await store.read('!a:x'), isNotNull);
    expect(await store.read('!b:x'), isNull);
    expect(await store.read('!c:x'), isNotNull);
  });

  test('asks what is showing only after the writes queued before it, so a '
      'thread another room just wrote is judged by its own '
      'notification', () async {
    final asked = <String>[];
    final first = store.write(
      _thread('!a:x', [_line(r'$a')]),
      showing: () async {
        asked.add('a');
        return {messageNotificationIdFor('!a:x')};
      },
    );
    final second = store.write(
      _thread('!b:x', [_line(r'$b')]),
      showing: () async {
        asked.add(await storeFile().exists() ? 'b after a' : 'b before a');
        return {
          messageNotificationIdFor('!a:x'),
          messageNotificationIdFor('!b:x'),
        };
      },
    );

    await Future.wait([first, second]);

    expect(asked, ['a', 'b after a']);
    expect(await store.read('!a:x'), isNotNull);
    expect(await store.read('!b:x'), isNotNull);
  });

  test(
    'keeps every other thread when what is showing cannot be read',
    () async {
      await store.write(_thread('!a:x', [_line(r'$1')]), showing: _showingNone);

      await store.write(
        _thread('!b:x', [_line(r'$2')]),
        showing: () async => null,
      );

      expect(await store.read('!a:x'), isNotNull);
      expect(await store.read('!b:x'), isNotNull);
    },
  );

  group('past the cap, with every thread still showing', () {
    final everyRoom = _showing([
      for (var i = 0; i <= maxNotificationThreads; i++) '!$i:x',
      '!new:x',
    ]);

    Future<void> fill() async {
      for (var i = 0; i < maxNotificationThreads; i++) {
        await store.write(
          _thread('!$i:x', [_line('\$$i')]),
          showing: everyRoom,
        );
      }
    }

    test('the least recently written goes', () async {
      await fill();

      await store.write(
        _thread('!new:x', [_line(r'$new')]),
        showing: everyRoom,
      );

      expect(await store.read('!0:x'), isNull);
      expect(await store.read('!1:x'), isNotNull);
      expect(await store.read('!new:x'), isNotNull);
    });

    test('rewriting a room already kept evicts nothing', () async {
      await fill();

      await store.write(
        _thread('!0:x', [_line(r'$again')]),
        showing: everyRoom,
      );

      for (var i = 0; i < maxNotificationThreads; i++) {
        expect(await store.read('!$i:x'), isNotNull);
      }
    });
  });

  test('clearing one room leaves the others', () async {
    await store.write(_thread('!a:x', [_line(r'$1')]), showing: _showingNone);
    await store.write(
      _thread('!b:x', [_line(r'$2')]),
      showing: _showing(['!a:x']),
    );

    await store.clear('!a:x');

    expect(await store.read('!a:x'), isNull);
    expect((await store.read('!b:x'))?.lines.single.eventId, r'$2');
  });

  test('a write that fails is reported, not thrown, and leaves no temporary '
      'file behind', () async {
    await dir.childDirectory(notificationThreadsFileName).create();

    await store.write(_thread('!a:x', [_line(r'$1')]), showing: _showingNone);

    expect((await dir.list().toList()).map((e) => e.basename), [
      notificationThreadsFileName,
    ]);
  });

  test('clearing everything deletes the file and any temporary file a crash '
      'left', () async {
    await store.write(_thread('!a:x', [_line(r'$1')]), showing: _showingNone);
    await dir
        .childFile('$notificationThreadsFileName.abc123')
        .writeAsString('{}');

    await store.clearAll();

    expect(await dir.list().isEmpty, isTrue);
    expect(await store.read('!a:x'), isNull);
  });

  test('survives a corrupt file rather than crashing the post', () async {
    await storeFile().writeAsString('not json');

    expect(await store.read('!a:x'), isNull);
  });

  group('shown at a preview level', () {
    final l10n = englishLocalizations;
    final thread = NotificationThread(
      roomId: '!r:x',
      title: 'Team',
      isGroupChat: true,
      lines: [
        StoredNotificationLine(
          eventId: r'$1',
          senderId: '@a:x',
          timestamp: DateTime.utc(2031),
          imageUri: 'content://zuno/1',
          imageMimeType: 'image/jpeg',
        ).rendered(
          senderName: 'Alice',
          senderAvatarUrl: Uri.parse('mxc://x/alice'),
          text: 'secret plans',
        ),
        StoredNotificationLine(
          eventId: r'$2',
          senderId: '@a:x',
          kind: NotificationLineKind.callSummary,
          timestamp: DateTime.utc(2031),
        ).rendered(senderName: 'Alice', text: 'Missed call'),
      ],
    );

    test('Name and message keeps everything', () {
      final shown = thread.shownAt(NotificationPreview.full, l10n);

      expect(shown.title, 'Team');
      expect(shown.lines.map((l) => l.text), ['secret plans', 'Missed call']);
      expect(shown.lines.first.stored.imageUri, 'content://zuno/1');
    });

    test('Name only keeps names and pictures of people, hides message text '
        "and photos, and keeps a missed call's own line", () {
      final shown = thread.shownAt(NotificationPreview.nameOnly, l10n);

      expect(shown.title, 'Team');
      expect(shown.lines.map((l) => l.text), ['New message', 'Missed call']);
      expect(shown.lines.first.senderName, 'Alice');
      expect(shown.lines.first.senderAvatarUrl, Uri.parse('mxc://x/alice'));
      expect(shown.lines.first.stored.imageUri, isNull);
    });

    test('Nothing keeps no text, names, pictures or photos', () {
      final shown = thread.shownAt(NotificationPreview.nothing, l10n);

      expect(shown.title, 'Zuno');
      expect(shown.lines.map((l) => l.text), ['New message', 'New message']);
      expect(shown.lines.map((l) => l.senderName), ['Zuno', 'Zuno']);
      expect(shown.lines.map((l) => l.senderAvatarUrl), [null, null]);
      expect(shown.lines.first.stored.imageUri, isNull);
      expect(shown.lines.map((l) => l.stored.eventId), [r'$1', r'$2']);
    });
  });
}
