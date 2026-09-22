import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_room_cache.dart';

void main() {
  test('encodes one room per line as id, kind, name', () {
    final encoded = encodeNotificationRoomCache([
      (id: '!a:x', name: 'Alice', isDirect: true),
      (id: '!g:x', name: 'Family chat', isDirect: false),
    ]);
    expect(encoded, '!a:x\td\tAlice\n!g:x\tg\tFamily chat');
  });

  test('strips tabs and newlines from names and skips empty ids', () {
    final encoded = encodeNotificationRoomCache([
      (id: '!a:x', name: 'Al\tice\nB', isDirect: true),
      (id: '', name: 'ghost', isDirect: true),
    ]);
    expect(encoded, '!a:x\td\tAl ice B');
  });

  test('writer stores the cache and skips unchanged rewrites', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final writer = NotificationRoomCacheWriter();
    final rooms = [(id: '!a:x', name: 'Alice', isDirect: true)];

    expect(await writer.write(prefs, rooms), isTrue);
    expect(prefs.getString(notificationRoomCacheKey), '!a:x\td\tAlice');
    expect(await writer.write(prefs, rooms), isFalse);
    expect(
      await writer.write(prefs, [(id: '!a:x', name: 'Al', isDirect: true)]),
      isTrue,
    );
    expect(prefs.getString(notificationRoomCacheKey), '!a:x\td\tAl');
  });

  MatrixEvent event({String type = 'm.room.message', String? stateKey}) =>
      MatrixEvent(
        type: type,
        content: const {},
        senderId: '@a:x',
        stateKey: stateKey,
        eventId: r'$e',
        originServerTs: DateTime.utc(2031),
      );

  SyncUpdate sync({
    List<MatrixEvent>? state,
    List<MatrixEvent>? timeline,
    Map<String, LeftRoomUpdate>? leave,
    List<BasicEvent>? accountData,
  }) => SyncUpdate(
    nextBatch: 'n',
    rooms: RoomsUpdate(
      join: {
        '!a:x': JoinedRoomUpdate(
          state: state,
          timeline: TimelineUpdate(events: timeline),
        ),
      },
      leave: leave,
    ),
    accountData: accountData,
  );

  group('notificationRoomCacheDirty', () {
    test('a sync with only messages, typing or receipts is clean', () {
      expect(notificationRoomCacheDirty(sync(timeline: [event()])), isFalse);
      expect(notificationRoomCacheDirty(SyncUpdate(nextBatch: 'n')), isFalse);
    });

    test('room state in the state block or the timeline is dirty', () {
      expect(
        notificationRoomCacheDirty(
          sync(
            state: [event(type: 'm.room.name', stateKey: '')],
          ),
        ),
        isTrue,
      );
      expect(
        notificationRoomCacheDirty(
          sync(
            timeline: [event(type: 'm.room.member', stateKey: '@b:x')],
          ),
        ),
        isTrue,
      );
    });

    test('leaving a room or a direct-chat change is dirty', () {
      expect(
        notificationRoomCacheDirty(sync(leave: {'!old:x': LeftRoomUpdate()})),
        isTrue,
      );
      expect(
        notificationRoomCacheDirty(
          sync(
            accountData: [BasicEvent(type: 'm.direct', content: const {})],
          ),
        ),
        isTrue,
      );
    });
  });

  test('writer reports whether it has written yet', () async {
    SharedPreferences.setMockInitialValues({});
    final writer = NotificationRoomCacheWriter();
    expect(writer.hasWritten, isFalse);
    await writer.write(await SharedPreferences.getInstance(), const []);
    expect(writer.hasWritten, isTrue);
  });
}
