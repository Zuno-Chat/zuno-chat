import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../failures.dart';
import '../native_http.dart';

class Answers<T> {
  final _waiting = Queue<Completer<T>>();
  final _ready = Queue<FutureOr<T> Function()>();
  Object? _closedWith;

  int get waiting => _waiting.length;

  Future<T> next() {
    if (_ready.isNotEmpty) return Future.sync(_ready.removeFirst());
    final closed = _closedWith;
    if (closed != null) return Future.error(closed);
    final answer = Completer<T>();
    _waiting.add(answer);
    return answer.future;
  }

  void answer(T value) {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(value);
    } else {
      _ready.add(() => value);
    }
  }

  void fail(Object error) {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(error);
    } else {
      _ready.add(() => throw error);
    }
  }

  void failAll(Object error) {
    _closedWith = error;
    _ready.clear();
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(error);
    }
  }
}

class ScriptedNativeHttp implements NativeHttp {
  void Function(NativeExchange exchange)? onOpen;
  final exchanges = <int, NativeExchange>{};
  final ended = <int>{};
  final statusAsked = <int>[];
  Object? readyFailure;
  var readyCalls = 0;

  Iterable<int> get opened => exchanges.keys;

  NativeExchange get last => exchanges.values.last;

  bool get allEnded => opened.every(ended.contains);

  NativeExchange _exchange(int id) {
    final exchange = exchanges[id];
    if (exchange == null) throw StateError('No request $id was opened');
    return exchange;
  }

  @override
  Future<void> ready() async {
    readyCalls++;
    final failure = readyFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<NativeHead> open(NativeRequest request) {
    final exchange = NativeExchange._(this, request);
    exchanges[request.id] = exchange;
    onOpen?.call(exchange);
    return exchange._head.future;
  }

  @override
  Future<BodyPull> pullBody(int id) => _exchange(id)._pulls.next();

  @override
  Future<BodyPull> write(int id, Uint8List chunk, {required bool last}) {
    final exchange = _exchange(id);
    if (exchange.cancelled) throw StateError('write after cancel');
    exchange.writes.add((chunk, last));
    return exchange._pulls.next();
  }

  @override
  Future<NativeChunk> read(int id) {
    final exchange = _exchange(id);
    exchange.reads++;
    return exchange._reads.next().then((chunk) {
      if (chunk.end) exchange._end();
      return chunk;
    });
  }

  @override
  Future<NativePhase> status(int id) async {
    statusAsked.add(id);
    return _exchange(id).phase;
  }

  @override
  Future<void> cancel(int id) async => _exchange(id)._cancel();
}

class NativeExchange {
  NativeExchange._(this._owner, this.request);

  final ScriptedNativeHttp _owner;
  final NativeRequest request;
  final _head = Completer<NativeHead>();
  final _reads = Answers<NativeChunk>();
  final _pulls = Answers<BodyPull>();
  final writes = <(Uint8List, bool)>[];
  var reads = 0;
  var cancelled = false;
  var headAlreadySent = false;
  var phase = NativePhase.waiting;

  int get id => request.id;

  int get pendingPulls => _pulls.waiting;

  List<int> get uploaded => [for (final (chunk, _) in writes) ...chunk];

  void answerHead(
    int status, {
    Map<String, List<String>> headers = const {},
    String? reason,
    bool endsUpload = true,
  }) {
    if (endsUpload) _pulls.answer(const BodyDone());
    _head.complete(
      NativeHead(status: status, headers: headers, reason: reason),
    );
  }

  void failOpen(HttpFailureKind kind, [String? detail]) {
    _end();
    _pulls.failAll(NativeHttpException(kind, detail ?? kind.name));
    _head.completeError(
      NativeHttpException(kind, detail ?? kind.name, request.url),
    );
  }

  void sendChunk(List<int> bytes) =>
      _reads.answer(NativeChunk(bytes: Uint8List.fromList(bytes)));

  void endBody({String? protocol}) =>
      _reads.answer(NativeChunk(end: true, protocol: protocol));

  void failRead(HttpFailureKind kind) {
    _end();
    _reads.fail(NativeHttpException(kind, kind.name, request.url));
  }

  void want(int max) => _pulls.answer(WantBytes(max));

  void rewind() => _pulls.answer(const Rewind());

  void _end() => _owner.ended.add(id);

  void _cancel() {
    if (cancelled) return;
    cancelled = true;
    _end();
    final error = NativeHttpException(
      HttpFailureKind.cancelled,
      'cancelled',
      request.url,
    );
    _pulls.failAll(error);
    _reads.failAll(error);
    if (!_head.isCompleted && !headAlreadySent) _head.completeError(error);
  }
}
