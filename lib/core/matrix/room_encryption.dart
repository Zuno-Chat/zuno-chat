import 'package:matrix/matrix.dart';

import 'undecryptable_event.dart';

bool sendsEncrypted(Room room) =>
    room.encrypted && room.client.encryptionEnabled;

bool sentInClear(List<Event> messages, Timeline timeline) =>
    timeline.room.encrypted &&
    messages.any((message) => _shownInClear(message.getDisplayEvent(timeline)));

bool _shownInClear(Event shown) {
  if (shown.redacted || shown.stateKey != null || isUndecryptableEvent(shown)) {
    return false;
  }
  if (_isLocalCopy(shown)) return !sendsEncrypted(shown.room);
  return shown.originalSource?.type != EventTypes.Encrypted;
}

bool _isLocalCopy(Event event) =>
    event.senderId == event.room.client.userID &&
    (event.unsigned?.containsKey(messageSendingStatusKey) ?? false);
