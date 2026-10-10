import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

class HeldSync {
  HeldSync(this.since, this.timeout, this.headers);

  final String? since;
  final String? timeout;
  final Map<String, String> headers;
  final _response = Completer<http.StreamedResponse>();
  bool aborted = false;

  bool get open => !_response.isCompleted;

  void answer(String nextBatch) {
    if (open) _response.complete(_json({'next_batch': nextBatch}));
  }

  void fail() {
    if (open) _response.completeError(http.ClientException('connection lost'));
  }

  void abort(Uri url) {
    if (!open) return;
    aborted = true;
    _response.completeError(http.RequestAbortedException(url));
  }
}

class FakeSyncServer extends http.BaseClient {
  final syncs = <HeldSync>[];

  Iterable<HeldSync> get waiting => syncs.where((sync) => sync.open);

  HeldSync get last => syncs.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final url = request.url;
    if (!url.path.endsWith('/sync')) {
      return Future.value(
        _json(url.path.endsWith('/filter') ? {'filter_id': '1'} : {}),
      );
    }
    final sync = HeldSync(
      url.queryParameters['since'],
      url.queryParameters['timeout'],
      Map.of(request.headers),
    );
    syncs.add(sync);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(() => sync.abort(url)));
    }
    return sync._response.future;
  }
}

http.StreamedResponse _json(Map<String, Object?> body) => http.StreamedResponse(
  Stream.fromIterable([utf8.encode(jsonEncode(body))]),
  200,
  headers: {'content-type': 'application/json'},
);

class SyncingFakeDatabaseApi extends FakeDatabaseApi {
  int cacheClears = 0;

  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<void> storeSyncFilterId(String syncFilterId) async {}

  @override
  Future<void> storePrevBatch(String prevBatch) async {}

  @override
  Future<void> clearCache() async => cacheClears++;

  @override
  Future<void> clear() async {}

  @override
  Future<void> deleteOldFiles(int savedAt) async {}

  @override
  Future<List<Never>> getToDeviceEventQueue() async => [];
}

T signInForSync<T extends Client>(T client) {
  client
    ..homeserver = Uri.parse('https://example.org')
    ..accessToken = 'token'
    ..setUserId('@me:example.org')
    ..syncErrorTimeoutSec = 0;
  return client;
}

Future<void> settleSync() => pumpEventQueue(times: 50);
