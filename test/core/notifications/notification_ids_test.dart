import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_ids.dart';

void main() {
  test('messageNotificationIdFor is FNV-1a over UTF-8, masked to 31 bits', () {
    expect(messageNotificationIdFor('!abc:example.org'), 1665439068);
    expect(messageNotificationIdFor('!room:matrix.org'), 1329869154);
    expect(messageNotificationIdFor(''), 18652613);
    expect(messageNotificationIdFor('!ünïcode:example.org'), 1478981488);
  });
}
