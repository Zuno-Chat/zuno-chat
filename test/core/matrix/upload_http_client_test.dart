import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:zuno/core/matrix/upload_http_client.dart';

import '../../helpers/fake_http.dart';

final _uploadUrl = Uri.parse('https://example.org/_matrix/media/v3/upload');

http.Request _upload(int bytes) =>
    http.Request('POST', _uploadUrl)
      ..bodyBytes = Uint8List.fromList(List.generate(bytes, (i) => i % 256));

class _Server extends http.BaseClient {
  _Server({this.chunkEvery, this.takeChunks});

  final Duration? chunkEvery;
  final int? takeChunks;
  final requests = <http.BaseRequest>[];
  final _answers = <Completer<http.StreamedResponse>>[];
  var aborted = 0;
  var bodyDone = false;

  void answer({Stream<List<int>>? body}) => _answers.last.complete(
    http.StreamedResponse(
      body ?? fakeTimeBody(utf8.encode('{"content_uri":"mxc://a/b"}')),
      200,
    ),
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    final answer = Completer<http.StreamedResponse>();
    _answers.add(answer);
    if (request case http.Abortable(:final abortTrigger?)) {
      abortTrigger.whenComplete(() {
        aborted++;
        if (!answer.isCompleted) {
          answer.completeError(http.RequestAbortedException(request.url));
        }
      });
    }
    var taken = 0;
    late final StreamSubscription<List<int>> body;
    body = request.finalize().listen((_) {
      taken++;
      if (takeChunks case final limit? when taken >= limit) {
        body.pause();
      } else if (chunkEvery case final every?) {
        body.pause();
        Timer(every, body.resume);
      }
    }, onDone: () => bodyDone = true);
    return answer.future;
  }
}

Matcher get _stalled => throwsA(
  isA<http.ClientException>().having(
    (e) => e.message,
    'message',
    contains('No progress'),
  ),
);

void main() {
  test('an upload reports progress chunk by chunk up to 1.0 to its scope, '
      'and its response passes through', () async {
    final client = UploadHttpClient(
      FakeHttpClient(
        (request) async => http.Response(jsonEncode({'ok': true}), 200),
      ),
    );
    addTearDown(client.close);
    final progress = <double>[];

    final response = await SendScope(onProgress: progress.add).run(
      () async =>
          http.Response.fromStream(await client.send(_upload(500 * 1024))),
    );

    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {'ok': true});
    expect(progress.length, greaterThan(1));
    expect(progress.any((p) => p > 0.0 && p < 1.0), isTrue);
    expect(progress.last, closeTo(1.0, 0.001));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('progress reaches only the scope the upload runs in', () async {
    final client = UploadHttpClient(
      FakeHttpClient((request) async => http.Response('{}', 200)),
    );
    addTearDown(client.close);
    final first = <double>[];
    final second = <double>[];

    await Future.wait([
      SendScope(onProgress: first.add)
          .run(() => client.send(_upload(64 * 1024 * 4))),
      SendScope(onProgress: second.add)
          .run(() => client.send(_upload(64 * 1024 * 2))),
      client.send(_upload(64 * 1024 * 3)),
    ]);

    expect(first, [0.25, 0.5, 0.75, 1.0]);
    expect(second, [0.5, 1.0]);
  });

  test('a request outside any send passes through untouched', () async {
    final server = _Server();
    final client = UploadHttpClient(server);

    final response = client.get(
      Uri.parse('https://example.org/_matrix/client/v3/sync'),
    );
    await Future<void>.delayed(Duration.zero);
    server.answer();

    expect((await response).statusCode, 200);
    expect(server.requests.single, isNot(isA<http.Abortable>()));
  });

  group('another request inside a send', () {
    final putUrl = Uri.parse(
      'https://example.org/_matrix/client/v3/rooms/!r/send/m.room.message/t1',
    );

    test('is stopped once it has had no answer for the stall limit', () {
      fakeAsync((async) {
        final server = _Server();
        final client = UploadHttpClient(server);

        Object? error;
        SendScope()
            .run(() => client.put(putUrl, body: '{}'))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.elapse(sendStallLimit - const Duration(seconds: 1));
        expect(server.aborted, 0);

        async.elapse(const Duration(seconds: 2));
        expect(server.aborted, 1);
        expect(() => throw error!, _stalled);
      });
    });

    test('reaches the next layer as a plain request with its body, so that '
        "layer's own deadlines still apply", () async {
      final server = _Server();
      final client = UploadHttpClient(server);

      final response = SendScope().run(
        () => client.put(putUrl, body: '{"body":"hi"}'),
      );
      await Future<void>.delayed(Duration.zero);
      server.answer();
      await response;

      final sent = server.requests.single;
      expect(sent, isA<http.Request>());
      expect((sent as http.Request).body, '{"body":"hi"}');
    });

    test('is not aborted when the send is stopped, and reports no '
        'progress', () async {
      final server = _Server();
      final client = UploadHttpClient(server);
      final scope = SendScope(onProgress: (_) => fail('no progress expected'));

      final response = scope.run(() => client.put(putUrl, body: '{}'));
      await Future<void>.delayed(Duration.zero);
      scope.stop();
      server.answer();

      expect((await response).statusCode, 200);
      expect(server.aborted, 0);
    });
  });

  test('a GET to the upload path passes through untouched', () async {
    final server = _Server();
    final client = UploadHttpClient(server);

    final response = client.get(_uploadUrl);
    await Future<void>.delayed(Duration.zero);
    server.answer();

    expect((await response).statusCode, 200);
    expect(server.requests.single, isNot(isA<http.Abortable>()));
  });

  group('a stalled upload', () {
    test('the server never answering after the last byte stops it once '
        'nothing has moved for the stall limit', () {
      fakeAsync((async) {
        final server = _Server();
        final client = UploadHttpClient(server);

        Object? error;
        client
            .send(_upload(200 * 1024))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        expect(server.bodyDone, isTrue);

        async.elapse(sendStallLimit - const Duration(seconds: 1));
        expect(error, isNull);
        expect(server.aborted, 0);

        async.elapse(const Duration(seconds: 2));
        expect(server.aborted, 1);
        expect(() => throw error!, _stalled);
      });
    });

    test('a body that stops being taken stops it', () {
      fakeAsync((async) {
        final server = _Server(takeChunks: 1);
        final client = UploadHttpClient(server);

        Object? error;
        client
            .send(_upload(200 * 1024))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.elapse(sendStallLimit + const Duration(seconds: 1));

        expect(server.bodyDone, isFalse);
        expect(server.aborted, 1);
        expect(() => throw error!, _stalled);
      });
    });

    test('a slow upload that keeps moving is never stopped', () {
      fakeAsync((async) {
        final server = _Server(
          chunkEvery: sendStallLimit - const Duration(seconds: 5),
        );
        final client = UploadHttpClient(server);

        http.StreamedResponse? response;
        client.send(_upload(64 * 1024 * 4)).then((r) => response = r);
        async.elapse(sendStallLimit * 4);
        expect(server.bodyDone, isTrue);
        server.answer();
        async.flushMicrotasks();

        expect(server.aborted, 0);
        expect(response?.statusCode, 200);
      });
    });

    test('once the answer starts, the stall limit no longer applies', () {
      fakeAsync((async) {
        final server = _Server();
        final client = UploadHttpClient(server);

        String? body;
        client
            .send(_upload(1024))
            .then(http.Response.fromStream)
            .then((r) => body = r.body);
        async.flushMicrotasks();
        server.answer(
          body: Stream.fromFuture(
            Future.delayed(sendStallLimit * 2, () => utf8.encode('late')),
          ),
        );
        async.elapse(sendStallLimit * 3);

        expect(server.aborted, 0);
        expect(body, 'late');
      });
    });
  });

  group('stopping a scope', () {
    test('aborts its upload on the way, and fails any later upload in it '
        'without sending it', () async {
      final server = _Server();
      final client = UploadHttpClient(server);
      final scope = SendScope();

      final first = scope.run(() => client.send(_upload(1024)));
      await Future<void>.delayed(Duration.zero);
      scope.stop();

      await expectLater(first, throwsA(isA<http.RequestAbortedException>()));
      await expectLater(
        scope.run(() => client.send(_upload(1024))),
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(server.requests, hasLength(1));
      expect(server.aborted, 1);
      expect(scope.isStopped, isTrue);
      await expectLater(scope.stopped, completes);
    });

    test('after its upload is answered changes nothing', () async {
      final server = _Server();
      final client = UploadHttpClient(server);
      final scope = SendScope();

      final response = scope.run(() => client.send(_upload(1024)));
      await Future<void>.delayed(Duration.zero);
      server.answer();
      final body = await http.Response.fromStream(await response);
      scope.stop();

      expect(body.statusCode, 200);
    });

    test('drops a real connection still waiting for its answer', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<void>();
      server.listen((request) async {
        await request.drain<void>();
        received.complete();
      });
      final client = UploadHttpClient(IOClient());
      addTearDown(client.close);
      final scope = SendScope();

      final upload = scope.run(
        () => client.send(
          http.Request(
            'POST',
            Uri.parse(
              'http://${server.address.host}:${server.port}'
              '/_matrix/media/v3/upload',
            ),
          )..bodyBytes = Uint8List(300 * 1024),
        ),
      );
      await received.future;
      scope.stop();

      await expectLater(
        upload.timeout(const Duration(seconds: 5)),
        throwsA(isA<http.RequestAbortedException>()),
      );
    });
  });
}
