import 'package:matrix/matrix.dart';

import 'undecryptable_event.dart';

Future<Event?> decryptAgain(
  Client client,
  Event event, {
  bool store = false,
}) async {
  final encryption = client.encryption;
  if (encryption == null) return null;
  final decrypted = await encryption.decryptRoomEvent(event, store: store);
  return isUndecryptableEvent(decrypted) ? null : decrypted;
}

Future<Event?> retryDecryptIfUndecryptable(Room room, Event event) async {
  if (!isUndecryptableEvent(event)) return null;
  final decrypted = await decryptAgain(room.client, event, store: true);
  if (decrypted == null) return null;
  room.lastEvent = decrypted;
  return decrypted;
}
