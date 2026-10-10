import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_thread_store.dart';

NotificationLine _line(String eventId, {String text = 'hi'}) =>
    NotificationLine(
      eventId: eventId,
      senderId: '@a:x',
      senderName: 'Alice',
      text: text,
      timestamp: DateTime.utc(2031, 1, 1, 12),
    );

NotificationThread _thread(String roomId, List<NotificationLine> lines) =>
    NotificationThread(
      roomId: roomId,
      title: 'Alice',
      isGroupChat: false,
      lines: lines,
    );

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('round-trips a thread with every field of its lines', () async {
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!r:x',
        title: 'Family',
        isGroupChat: true,
        lines: [
          _line(r'$1'),
          NotificationLine(
            eventId: r'$2',
            senderId: '@b:x',
            senderName: 'Bob',
            senderAvatarUrl: Uri.parse('mxc://x/bob'),
            text: 'a cat',
            timestamp: DateTime.utc(2031, 1, 1, 13),
            placeholder: true,
            imageUri: 'content://zuno/1',
            imageMimeType: 'image/jpeg',
            quiet: true,
          ),
        ],
      ),
    );

    final thread = readNotificationThread(prefs, '!r:x')!;
    expect(thread.title, 'Family');
    expect(thread.isGroupChat, isTrue);
    expect(thread.lines.map((l) => l.text), ['hi', 'a cat']);
    final first = thread.lines.first;
    expect(first.timestamp, DateTime.utc(2031, 1, 1, 12));
    expect(first.placeholder, isFalse);
    expect(first.quiet, isFalse);
    final line = thread.lines.last;
    expect(line.eventId, r'$2');
    expect(line.senderId, '@b:x');
    expect(line.senderName, 'Bob');
    expect(line.senderAvatarUrl, Uri.parse('mxc://x/bob'));
    expect(line.placeholder, isTrue);
    expect(line.imageUri, 'content://zuno/1');
    expect(line.imageMimeType, 'image/jpeg');
    expect(line.quiet, isTrue);
  });

  test('a line stored before placeholders and quiet lines existed reads as '
      'a loud, real message', () async {
    await prefs.setString(
      notificationThreadsKey,
      jsonEncode({
        '!r:x': {
          'title': 'Alice',
          'lines': [
            {'senderId': '@a:x', 'text': 'hi', 'ts': 0},
          ],
        },
      }),
    );

    final line = readNotificationThread(prefs, '!r:x')!.lines.single;
    expect(line.placeholder, isFalse);
    expect(line.quiet, isFalse);
    expect(line.senderName, '@a:x');
  });

  test('is empty for a room never posted', () {
    expect(readNotificationThread(prefs, '!nope:x'), isNull);
  });

  test('keeps only the newest lines', () async {
    await writeNotificationThread(
      prefs,
      _thread('!r:x', [
        for (var i = 0; i < maxNotificationLines + 3; i++) _line('\$$i'),
      ]),
    );

    final stored = readNotificationThread(prefs, '!r:x')!;
    expect(stored.lines, hasLength(maxNotificationLines));
    expect(stored.lines.last.eventId, '\$${maxNotificationLines + 2}');
  });

  test('clearing one room leaves the others', () async {
    await writeNotificationThread(prefs, _thread('!a:x', [_line(r'$1')]));
    await writeNotificationThread(prefs, _thread('!b:x', [_line(r'$2')]));

    await clearNotificationThread(prefs, '!a:x');

    expect(readNotificationThread(prefs, '!a:x'), isNull);
    expect(readNotificationThread(prefs, '!b:x')?.lines.single.eventId, r'$2');
  });

  test('clearing everything forgets every room', () async {
    await writeNotificationThread(prefs, _thread('!a:x', [_line(r'$1')]));

    await clearAllNotificationThreads(prefs);

    expect(readNotificationThread(prefs, '!a:x'), isNull);
  });

  test('survives a corrupt store rather than crashing the post', () async {
    await prefs.setString(notificationThreadsKey, 'not json');

    expect(readNotificationThread(prefs, '!a:x'), isNull);
  });
}
