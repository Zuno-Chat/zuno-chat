import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

class PushTestClient extends Client {
  PushTestClient({this.signedIn = true, this.disposing, super.httpClient})
    : super('test', database: FakeDatabaseApi());

  bool signedIn;
  final Future<void>? disposing;
  Event? Function(PushNotification notification)? pushedEvent;
  final fetched = <String?>[];
  int disposeCalls = 0;
  bool? closedDatabase;

  @override
  bool isLogged() => signedIn;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    fetched.add(notification.eventId);
    return pushedEvent?.call(notification);
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposeCalls++;
    closedDatabase = closeDatabase;
    await disposing;
  }
}
