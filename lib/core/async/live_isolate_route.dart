import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

const liveRouteProbeWithin = _staleAfter;
const liveRouteAcceptWithin = Duration(seconds: 4);
const liveRouteDoneWithin = Duration(seconds: 25);
const _staleAfter = Duration(seconds: 2);

const _ping = 'ping';
const _pong = 'pong';
const _accepted = 'accepted';
const _refused = 'refused';
const _done = 'done';

Future<bool> answersPing(
  SendPort port, {
  Duration within = liveRouteProbeWithin,
}) async {
  final replies = ReceivePort();
  try {
    port.send({_ping: replies.sendPort});
    final answer = await replies.first.timeout(within, onTimeout: () => null);
    return answer == _pong;
  } finally {
    replies.close();
  }
}

bool answerPing(Object? message) {
  if (message is! Map) return false;
  final replyTo = message[_ping];
  if (replyTo is! SendPort) return false;
  replyTo.send(_pong);
  return true;
}

Future<bool> handOffToLiveIsolate(
  String portName,
  Map<String, Object?> message, {
  Duration probeWithin = liveRouteProbeWithin,
  Duration acceptWithin = liveRouteAcceptWithin,
  Duration doneWithin = liveRouteDoneWithin,
}) async {
  final port = IsolateNameServer.lookupPortByName(portName);
  if (port == null) return false;
  if (!await answersPing(port, within: probeWithin)) return false;
  final replies = ReceivePort();
  final answers = StreamIterator<Object?>(replies);
  try {
    port.send({
      ...message,
      'replyTo': replies.sendPort,
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (!await _nextAnswer(answers, acceptWithin)) return false;
    if (answers.current != _accepted) return false;
    return await _nextAnswer(answers, doneWithin) && answers.current == _done;
  } finally {
    await answers.cancel();
    replies.close();
  }
}

Future<bool> _nextAnswer(StreamIterator<Object?> answers, Duration within) =>
    answers.moveNext().timeout(within, onTimeout: () => false);

class LiveRouteMessage {
  LiveRouteMessage._(this.body, this._replyTo, this._sentAt);

  static LiveRouteMessage? from(Object? message) {
    if (message is! Map) return null;
    final replyTo = message['replyTo'];
    final sentAt = message['sentAt'];
    return LiveRouteMessage._(
      message,
      replyTo is SendPort ? replyTo : null,
      sentAt is int ? sentAt : null,
    );
  }

  final Map<Object?, Object?> body;
  final SendPort? _replyTo;
  final int? _sentAt;

  bool get stale {
    final sentAt = _sentAt;
    if (sentAt == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - sentAt;
    return age > _staleAfter.inMilliseconds;
  }

  void accept() => _replyTo?.send(_accepted);

  void refuse() => _replyTo?.send(_refused);

  void finish() => _replyTo?.send(_done);
}
