import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'fake_encryption.dart';
import 'fake_matrix.dart';

class PushTestClient extends Client with TestDecryption {
  PushTestClient({
    this.signedIn = true,
    this.disposing,
    this.decryption,
    super.httpClient,
  }) : super('test', database: FakeDatabaseApi());

  bool signedIn;
  final Future<void>? disposing;
  @override
  final Encryption? decryption;
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
