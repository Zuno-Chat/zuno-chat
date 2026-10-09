import 'dart:async';

import 'package:matrix/matrix.dart';

import 'call_member_state.dart';

const _writeHold = Duration(seconds: 5);

final _writers = Expando<_OwnCallMembershipWriter>('own call membership');

Future<String> writeOwnCallMembership(
  Client client,
  String roomId,
  Map<String, Object?> content,
) => (_writers[client] ??= _OwnCallMembershipWriter(
  client,
)).write(roomId, content);

class _OwnCallMembershipWriter {
  _OwnCallMembershipWriter(this._client);

  final Client _client;
  final _tails = <String, Future<void>>{};
  final _latest = <String, Map<String, Object?>>{};

  Future<String> write(String roomId, Map<String, Object?> content) {
    _latest[roomId] = content;
    final sent = Completer<String>();
    final tail = (_tails[roomId] ?? Future<void>.value()).then(
      (_) => _send(roomId, content, sent),
    );
    _tails[roomId] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[roomId], tail)) _tails.remove(roomId);
      }),
    );
    return sent.future;
  }

  Future<void> _send(
    String roomId,
    Map<String, Object?> content,
    Completer<String> sent,
  ) async {
    final Future<String> request;
    try {
      request = _client.setRoomStateWithKey(
        roomId,
        callMemberEventType,
        _client.userID!,
        content,
      );
    } catch (error, stackTrace) {
      sent.completeError(error, stackTrace);
      return;
    }
    var outlived = false;
    unawaited(
      request
          .then<void>(sent.complete, onError: sent.completeError)
          .whenComplete(() {
            if (outlived) _writeLatestAgain(roomId, content);
          }),
    );
    await sent.future
        .then<void>((_) {}, onError: (Object _) {})
        .timeout(
          _writeHold,
          onTimeout: () {
            outlived = true;
          },
        );
  }

  void _writeLatestAgain(String roomId, Map<String, Object?> stale) {
    final latest = _latest[roomId];
    if (latest == null || identical(latest, stale)) return;
    unawaited(write(roomId, latest).then<void>((_) {}, onError: (Object _) {}));
  }
}
