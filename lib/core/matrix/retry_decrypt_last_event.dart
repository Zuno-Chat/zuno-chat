import 'package:matrix/matrix.dart';

import 'undecryptable_event.dart';

Future<Event?> retryDecryptIfUndecryptable(Room room, Event event) async {
  final encryption = room.client.encryption;
  if (!isUndecryptableEvent(event) || encryption == null) return null;

  final decrypted = await encryption.decryptRoomEvent(event, store: true);
  if (isUndecryptableEvent(decrypted)) return null;

  room.lastEvent = decrypted;
  return decrypted;
}
