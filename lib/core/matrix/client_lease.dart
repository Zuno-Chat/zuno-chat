import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';

enum ClientLeaseKind { app, background }

const appLeaseWait = Duration(seconds: 5);
const backgroundLeaseWait = Duration(seconds: 8);
const _replyGrace = Duration(seconds: 2);

class ClientLeaseDenied implements Exception {
  const ClientLeaseDenied();

  @override
  String toString() =>
      'ClientLeaseDenied: another Matrix client holds the store';
}

class ClientLease {
  ClientLease._(this.token, this._letGo);

  final String? token;
  final Future<void> Function() _letGo;
  bool _released = false;

  Future<void> release() {
    if (_released) return Future.value();
    _released = true;
    return _letGo();
  }
}

class _Turn {
  _Turn(this.granted);

  final Completer<bool> granted;
  Timer? timeout;
}

class ClientLeases {
  ClientLeases({
    PlatformCapabilities? capabilities,
    this.channel = const MethodChannel('zuno/client_lease'),
  }) : _injectedCapabilities = capabilities;

  static final instance = ClientLeases();

  final PlatformCapabilities? _injectedCapabilities;
  final MethodChannel channel;
  final _yields = StreamController<void>.broadcast();
  final _waiting = Queue<_Turn>();
  bool _turnTaken = false;
  bool _answering = false;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Stream<void> get yieldRequests => _yields.stream;

  Future<ClientLease> acquire(ClientLeaseKind kind, {Duration? wait}) async {
    final patience =
        wait ??
        (kind == ClientLeaseKind.app ? appLeaseWait : backgroundLeaseWait);
    if (!_capabilities.clientLease) return ClientLease._(null, _nothing);
    _answerYields();
    if (kind == ClientLeaseKind.app) {
      final (:token, denied: _) = await _ask(kind, patience);
      return ClientLease._(token, () => _letGo(token));
    }
    final (:token, :denied) = await _ask(kind, await _takeTurn(patience));
    if (denied) {
      _passTurn();
      throw const ClientLeaseDenied();
    }
    return ClientLease._(token, () async {
      try {
        await _letGo(token);
      } finally {
        _passTurn();
      }
    });
  }

  Future<_Answer> _ask(ClientLeaseKind kind, Duration wait) async {
    final reply = channel.invokeMethod<String>('acquire', {
      'kind': kind.name,
      'waitMs': wait.inMilliseconds,
    });
    try {
      final token = await reply.timeout(wait + _replyGrace);
      return (token: token, denied: token == null);
    } on TimeoutException {
      if (kind == ClientLeaseKind.background) {
        unawaited(reply.then(_letGo, onError: (_) {}));
      }
      debugPrint('zuno/db: no answer about the client lease (${kind.name})');
      return _unanswered;
    } on MissingPluginException {
      return _unchecked;
    } catch (e) {
      debugPrint('zuno/db: the client lease could not be checked ($e)');
      return _unchecked;
    }
  }

  Future<void> _letGo(String? token) async {
    if (token == null) return;
    try {
      await channel.invokeMethod<void>('release', {'token': token});
    } catch (e) {
      debugPrint('zuno/db: the client lease was not given back ($e)');
    }
  }

  void _answerYields() {
    if (_answering) return;
    _answering = true;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'yield') {
        throw MissingPluginException('zuno/client_lease has no ${call.method}');
      }
      _yields.add(null);
      return null;
    });
  }

  Future<Duration> _takeTurn(Duration wait) async {
    if (!_turnTaken) {
      _turnTaken = true;
      return wait;
    }
    final watch = Stopwatch()..start();
    final turn = _Turn(Completer<bool>());
    _waiting.add(turn);
    turn.timeout = Timer(wait, () {
      if (!_waiting.remove(turn)) return;
      turn.granted.complete(false);
    });
    if (!await turn.granted.future) throw const ClientLeaseDenied();
    final left = wait - watch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void _passTurn() {
    if (_waiting.isEmpty) {
      _turnTaken = false;
      return;
    }
    final next = _waiting.removeFirst();
    next.timeout?.cancel();
    next.granted.complete(true);
  }
}

typedef _Answer = ({String? token, bool denied});

const _Answer _unchecked = (token: null, denied: false);
const _Answer _unanswered = (token: null, denied: true);

Future<void> _nothing() async {}
