import 'package:matrix/matrix.dart';

import 'undecryptable_event.dart';

Future<Event?> decryptAgain(Client client, Event event) async {
  final encryption = client.encryption;
  if (encryption == null) return null;
  final decrypted = await encryption.decryptRoomEvent(event);
  return isUndecryptableEvent(decrypted) ? null : decrypted;
}
