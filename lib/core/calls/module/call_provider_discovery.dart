import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import '../../matrix/account/saved_server_answer.dart';
import '../../matrix/http/bearer_authorization.dart';
import '../../matrix/http/typed_server_answers.dart';
import 'calls_module.dart';

enum CallsOffer { none, cloudflare, livekit }

class CallsNotOffered implements Exception {
  const CallsNotOffered();

  @override
  String toString() => 'CallsNotOffered: the server offers no calls';
}

const _cacheKey = 'zuno.calls_offer';
const _staleAfter = Duration(days: 1);

typedef _Saved = ({CallsOffer offer, DateTime savedAt});

class CallProviderDiscovery {
  CallProviderDiscovery({required this._client, this._httpClient}) {
    _loaded = _load();
    _loginSub = _client.onLoginStateChanged.stream.listen(_onLoginState);
    if (_client.isLogged()) {
      unawaited(_loaded.then((_) => refreshIfStale()));
    }
  }

  final Client _client;
  final http.Client? _httpClient;
  final _changes = StreamController<CallsOffer?>.broadcast();
  late final Future<void> _loaded;
  late final StreamSubscription<LoginState> _loginSub;
  _Saved? _saved;
  Future<CallsOffer>? _inflight;
  int _generation = 0;
  bool _disposed = false;

  Stream<CallsOffer?> get offers {
    late final StreamController<CallsOffer?> controller;
    StreamSubscription<CallsOffer?>? changes;
    controller = StreamController<CallsOffer?>(
      onListen: () async {
        await _loaded;
        if (controller.isClosed || !controller.hasListener) return;
        controller.add(_saved?.offer);
        changes = _changes.stream.listen(controller.add);
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  Future<CallsOffer> current() async {
    await _loaded;
    return _usable?.offer ?? _request();
  }

  Future<CallsOffer> refetch() async {
    await _loaded;
    return _request();
  }

  Future<void> refreshIfStale() async {
    try {
      await _loaded;
      if (_usable case final saved? when isFresh(saved.savedAt, _staleAfter)) {
        return;
      }
      await _request();
    } catch (error, stack) {
      if (!isExpectedCallsFailure(error)) {
        reportCaught('discover the call provider', error, stack);
      }
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_loginSub.cancel());
    unawaited(_changes.close());
  }

  _Saved? get _usable => switch (_saved) {
    final saved? when saved.offer != CallsOffer.none => saved,
    _ => null,
  };

  Future<void> _load() async {
    try {
      final saved = await readSavedServerAnswer(_client, _cacheKey);
      final offer = CallsOffer.values.asNameMap()[saved?.content['offer']];
      if (saved != null && offer != null && _saved == null) {
        _saved = (offer: offer, savedAt: saved.savedAt);
      }
    } catch (error, stack) {
      reportUnlessServerOrNetwork('read the saved call provider', error, stack);
    }
  }

  void _onLoginState(LoginState state) {
    switch (state) {
      case LoginState.loggedIn:
        unawaited(refreshIfStale());
      case LoginState.loggedOut:
        _generation++;
        _inflight = null;
        _saved = null;
        if (!_disposed) _changes.add(null);
      case LoginState.softLoggedOut:
        break;
    }
  }

  Future<CallsOffer> _request() {
    final existing = _inflight;
    if (existing != null) return existing;
    late final Future<CallsOffer> started;
    started = _fetch().whenComplete(() {
      if (identical(_inflight, started)) _inflight = null;
    });
    return _inflight = started;
  }

  Future<CallsOffer> _fetch() async {
    final generation = _generation;
    final offer = await _ask();
    if (generation != _generation || _disposed) return offer;
    final changed = offer != _saved?.offer;
    _saved = (offer: offer, savedAt: clock.now());
    if (changed) _changes.add(offer);
    try {
      await saveServerAnswer(_client, _cacheKey, {'offer': offer.name});
    } catch (error, stack) {
      reportUnlessServerOrNetwork('save the call provider', error, stack);
    }
    return offer;
  }

  Future<CallsOffer> _ask() async {
    final Map<String, dynamic> body;
    try {
      body = await sendToCallsModule(
        method: 'GET',
        uri: callsModuleUri(_client, const ['config']),
        request: 'GET /config',
        resendable: true,
        authorization: () => bearerAuthorization(_client),
        httpClient: _httpClient,
      );
    } on CallsRouteGone {
      return CallsOffer.none;
    } on FormatException {
      return CallsOffer.none;
    } on CallsModuleException catch (error) {
      if (error.statusCode == 404) return CallsOffer.none;
      rethrow;
    }
    return switch (body['provider']) {
      'cloudflare' => CallsOffer.cloudflare,
      'livekit' => CallsOffer.livekit,
      _ => CallsOffer.none,
    };
  }
}
