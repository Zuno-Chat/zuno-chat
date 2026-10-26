import 'dart:async';

import 'package:matrix/matrix.dart';

class SendRecordingRoom extends Room {
  SendRecordingRoom({required super.client, super.id = '!room:example.org'});

  final requests =
      <
        ({
          Map<String, dynamic> content,
          String type,
          String? txid,
          bool pendingCopy,
        })
      >[];
  final sentEvents = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get attempts => [
    for (final request in requests) request.content,
  ];

  List<bool> get pendingCopies => [
    for (final request in requests) request.pendingCopy,
  ];
  bool undelivered = false;
  Object? sendError;
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
    requests.add((
      content: content,
      type: type,
      txid: txid,
      pendingCopy: displayPendingEvent,
    ));
    await sendGate?.future;
    if (sendError case final error?) throw error;
    if (undelivered) return null;
    sentEvents.add(content);
    return client.generateUniqueTransactionId();
  }
}
