import 'dart:async';

import 'package:matrix/matrix.dart';

class SendRecordingRoom extends Room {
  SendRecordingRoom({required super.client, super.id = '!room:example.org'});

  final attempts = <Map<String, dynamic>>[];
  final pendingCopies = <bool>[];
  final sentEvents = <Map<String, dynamic>>[];
  bool undelivered = false;
  Completer<void>? sendGate;

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    attempts.add(content);
    pendingCopies.add(displayPendingEvent);
    await sendGate?.future;
    if (undelivered) return null;
    sentEvents.add(content);
    return client.generateUniqueTransactionId();
  }
}
