import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno_http/testing.dart';
import 'package:zuno_http/zuno_http.dart';

import 'support/expectations.dart';

final _url = Uri.parse('https://example.org/_matrix/client/v3/sync?since=s1');

void main() {
  late ScriptedNativeHttp native;
  late ZunoHttpClient client;
  late bool leftOpenOnPurpose;

  setUp(() {
    native = ScriptedNativeHttp();
    client = ZunoHttpClient(
      userAgent: agent,
      deadlines: serviceDeadlines,
      native: native,
    );
    leftOpenOnPurpose = false;
  });

  tearDown(() async {
    await pumpEventQueue();
    if (!leftOpenOnPurpose) {
      expect(native.allEnded, isTrue, reason: 'a native request never ended');
    }
  });

  void serve(
    int status, {
    Map<String, List<String>> headers = const {},
    List<String> chunks = const [],
    String? protocol,
    int? want,
  }) {
    native.onOpen = (exchange) {
      if (want != null) exchange.want(want);
      exchange.answerHead(status, headers: headers);
      for (final chunk in chunks) {
        exchange.sendChunk(utf8.encode(chunk));
      }
      exchange.endBody(protocol: protocol);
    };
  }

  group('responses', () {
    test('return the status, body and headers', () async {
      serve(
        200,
        headers: {
          'Content-Type': ['text/plain'],
        },
        chunks: ['hel', 'lo'],
      );

      final response = await client.get(_url);

      expect(response.statusCode, 200);
      expect(response.body, 'hello');
      expect(response.headers['content-type'], 'text/plain');
    });

    test(
      'lower-case header names and join repeated values with commas',
      () async {
        serve(
          200,
          headers: {
            'Link': ['<a>', '<b> '],
            'link': ['<c>'],
          },
        );

        final response = await client.get(_url);

        expect(response.headers['link'], '<a>,<b>,<c>');
        expect(response.headers.containsKey('Link'), isFalse);
      },
    );

    test('report no content length for an encoded body', () async {
      serve(
        200,
        headers: {
          'content-encoding': ['br'],
          'content-length': ['10'],
        },
        chunks: ['decoded body longer than ten'],
      );

      final response = await client.send(http.Request('GET', _url));
      await response.stream.drain<void>();

      expect(response.contentLength, isNull);
    });

    test('report no content length for a negative one', () async {
      serve(
        200,
        headers: {
          'content-length': ['-1'],
        },
        chunks: ['x'],
      );

      final response = await client.send(http.Request('GET', _url));
      await response.stream.drain<void>();

      expect(response.contentLength, isNull);
    });

    test('report the content length of a plain body', () async {
      serve(
        200,
        headers: {
          'content-length': ['5'],
        },
        chunks: ['hello'],
      );

      final response = await client.send(http.Request('GET', _url));
      await response.stream.drain<void>();

      expect(response.contentLength, 5);
    });

    test('end a 204 at once and drain the native request', () async {
      native.onOpen = (exchange) => exchange.answerHead(204);

      final response = await client.send(http.Request('PUT', _url));
      final body = await response.stream.toBytes();

      expect(body, isEmpty);
      native.last.endBody();
      await pumpEventQueue();
    });

    test('end a HEAD at once and keep its declared length', () async {
      native.onOpen = (exchange) {
        exchange.answerHead(
          200,
          headers: {
            'content-length': ['100'],
          },
        );
        exchange.endBody();
      };

      final response = await client.send(http.Request('HEAD', _url));

      expect(await response.stream.toBytes(), isEmpty);
      expect(response.contentLength, 100);
    });

    test('carry the request URL when no redirect was followed', () async {
      serve(200);

      final response = await client.send(http.Request('GET', _url));
      await response.stream.drain<void>();

      expect((response as http.BaseResponseWithUrl).url, _url);
    });

    test('read no further while the listener is paused', () async {
      native.onOpen = (exchange) {
        exchange.answerHead(200);
        exchange.sendChunk([1]);
      };

      final response = await client.send(http.Request('GET', _url));
      final subscription = response.stream.listen((_) {});
      await pumpEventQueue();
      subscription.pause();
      final readsWhenPaused = native.last.reads;
      native.last.sendChunk([2]);
      native.last.sendChunk([3]);
      await pumpEventQueue();

      expect(native.last.reads, lessThanOrEqualTo(readsWhenPaused + 1));
      await subscription.cancel();
    });

    test('a failed read errors the body as its kind', () async {
      native.onOpen = (exchange) {
        exchange.answerHead(200);
        exchange.sendChunk([1]);
        exchange.failRead(HttpFailureKind.connectionLost);
      };

      final response = await client.send(http.Request('GET', _url));

      await expectLater(
        response.stream.toBytes(),
        throwsA(
          isA<NativeHttpException>().having(
            (e) => e.kind,
            'kind',
            HttpFailureKind.connectionLost,
          ),
        ),
      );
    });

    test(
      'print the protocol at the end of a body outside release builds',
      () async {
        final lines = <String?>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => lines.add(message);
        addTearDown(() => debugPrint = original);
        serve(200, chunks: ['x'], protocol: 'h3');

        await client.get(_url);

        expect(lines, ['zuno/http: GET example.org h3']);
      },
    );
  });

  group('requests', () {
    test('send the client User-Agent', () async {
      serve(200);

      await client.get(_url);

      expect(native.last.request.headers['user-agent'], agent);
    });

    test('keep a caller User-Agent', () async {
      serve(200);

      await client.get(_url, headers: {'User-Agent': 'Map tiles'});

      expect(native.last.request.headers.values, contains('Map tiles'));
      expect(native.last.request.headers.values, isNot(contains(agent)));
    });

    test('drop a caller Host header', () async {
      serve(200);

      await client.get(_url, headers: {'Host': 'elsewhere.example'});

      expect(
        native.last.request.headers.keys.map((name) => name.toLowerCase()),
        isNot(contains('host')),
      );
    });

    test('send nothing native for http', () async {
      await expectLater(
        client.get(Uri.parse('http://192.168.1.2/x')),
        throwsA(isA<CleartextRefusedException>()),
      );
      expect(native.opened, isEmpty);
    });

    test('send a GET without a body', () async {
      serve(200);

      await client.get(_url);

      expect(native.last.request.hasBody, isFalse);
      expect(native.last.request.bodyLength, isNull);
      expect(native.last.pendingPulls, 0);
    });

    test('a native open failure surfaces as its kind', () async {
      native.onOpen = (exchange) => exchange.failOpen(HttpFailureKind.dns);

      await expectLater(
        client.get(_url),
        throwsA(
          isA<NativeHttpException>().having(
            (e) => e.kind,
            'kind',
            HttpFailureKind.dns,
          ),
        ),
      );
    });

    test(
      'an open cancelled natively becomes RequestAbortedException',
      () async {
        native.onOpen = (exchange) =>
            exchange.failOpen(HttpFailureKind.cancelled);

        await expectLater(
          client.get(_url),
          throwsA(isA<http.RequestAbortedException>()),
        );
      },
    );
  });

  group('request bodies', () {
    test(
      'get application/octet-stream when they have no content type',
      () async {
        final request = http.Request('POST', _url)..bodyBytes = [1, 2, 3];
        serve(200, want: 3);

        await (await client.send(request)).stream.drain<void>();

        expect(
          native.last.request.headers['content-type'],
          'application/octet-stream',
        );
      },
    );

    test('keep their own content type', () async {
      serve(200, want: 64);

      await client.post(
        _url,
        headers: {'Content-Type': 'application/json'},
        body: '{}',
      );

      expect(native.last.request.headers.values, contains('application/json'));
      expect(
        native.last.request.headers.values,
        isNot(contains('application/octet-stream')),
      );
    });

    test('pass a known length and are never sent chunked', () async {
      final request = http.Request('PUT', _url)..bodyBytes = List.filled(10, 7);
      serve(200, want: 10);

      await (await client.send(request)).stream.drain<void>();

      expect(native.last.request.hasBody, isTrue);
      expect(native.last.request.bodyLength, 10);
    });

    test(
      'are written only when asked, at most the asked size, marking the last',
      () async {
        final request = http.Request('POST', _url)
          ..bodyBytes = List.generate(10, (i) => i);
        final sent = client.send(request);
        await pumpEventQueue();
        final exchange = native.last;

        expect(exchange.writes, isEmpty);
        exchange.want(4);
        await pumpEventQueue();
        exchange.want(4);
        await pumpEventQueue();
        exchange.want(4);
        await pumpEventQueue();
        exchange.answerHead(200);
        exchange.endBody();
        await (await sent).stream.drain<void>();

        expect(
          [for (final (chunk, _) in exchange.writes) chunk.length],
          [4, 4, 2],
        );
        expect(
          [for (final (_, last) in exchange.writes) last],
          [false, false, true],
        );
        expect(exchange.uploaded, List.generate(10, (i) => i));
      },
    );

    test('that fail after the answer fail the response and cancel', () async {
      final request = http.StreamedRequest('POST', _url)..sink.add([1, 2]);
      final sent = client.send(request);
      await pumpEventQueue();
      native.last.want(10);
      await pumpEventQueue();
      native.last.answerHead(200, endsUpload: false);
      final response = await sent;
      final failure = expectLater(
        response.stream.drain<void>(),
        throwsA(isA<StateError>()),
      );

      request.sink
        ..addError(StateError('the file went away'))
        ..close().ignore();
      await failure;

      expect(native.last.cancelled, isTrue);
    });

    test('nobody asked for are still let go when the request ends', () async {
      final request = _SourceRequest(_url, length: 3);
      native.onOpen = (exchange) => exchange
        ..answerHead(401)
        ..endBody();

      await (await client.send(request)).stream.drain<void>();
      await pumpEventQueue();

      expect(request.listened, isTrue);
      expect(request.cancelled, isTrue);
    });

    test('of length zero are let go unread', () async {
      final request = _SourceRequest(_url, length: 0);
      serve(204);

      await client.send(request);
      await pumpEventQueue();

      expect(native.last.request.hasBody, isFalse);
      expect(request.cancelled, isTrue);
    });

    test(
      'waiting on their source are let go when the request is aborted',
      () async {
        final abort = Completer<void>();
        final request = _SourceRequest(_url, abortTrigger: abort.future);
        final sent = client.send(request);
        await pumpEventQueue();
        native.last.want(10);
        await pumpEventQueue();
        expect(request.listened, isTrue);

        abort.complete();

        await expectLater(sent, throwsA(isA<http.RequestAbortedException>()));
        await pumpEventQueue();
        expect(request.cancelled, isTrue);
      },
    );

    test('in memory restart from their first byte on rewind', () async {
      final request = http.Request('PUT', _url)..bodyBytes = [1, 2, 3, 4];
      native.onOpen = (exchange) {
        exchange.want(4);
        exchange.rewind();
        exchange.want(4);
      };

      final sent = client.send(request);
      await pumpEventQueue();
      native.last
        ..answerHead(200)
        ..endBody();
      await (await sent).stream.drain<void>();

      expect(
        [for (final (chunk, _) in native.last.writes) chunk],
        [
          [1, 2, 3, 4],
          [1, 2, 3, 4],
        ],
      );
    });

    test(
      'that know how to rewind themselves restart from their own replay',
      () async {
        final request = _RewindableRequest(_url, [5, 6]);
        native.onOpen = (exchange) {
          exchange.want(8);
          exchange.rewind();
          exchange.want(8);
        };

        final sent = client.send(request);
        await pumpEventQueue();
        native.last
          ..answerHead(200)
          ..endBody();
        await (await sent).stream.drain<void>();

        expect(request.rewinds, 1);
        expect(native.last.uploaded, [5, 6, 5, 6]);
      },
    );

    test(
      'streamed cancel the native request on rewind as a lost connection',
      () async {
        final request = http.StreamedRequest('PUT', _url)..contentLength = 3;
        request.sink
          ..add([1, 2, 3])
          ..close();
        native.onOpen = (exchange) => exchange
          ..want(3)
          ..rewind();

        await expectLater(
          client.send(request),
          throwsA(failsAs(HttpFailureKind.connectionLost)),
        );
        expect(native.last.cancelled, isTrue);
      },
    );

    test('shorter than their content length fail and cancel', () async {
      final request = http.StreamedRequest('PUT', _url)..contentLength = 5;
      request.sink
        ..add([1, 2, 3])
        ..close();
      native.onOpen = (exchange) => exchange.want(5);

      await expectLater(
        client.send(request),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('Content size below specified contentLength'),
          ),
        ),
      );
      expect(native.last.cancelled, isTrue);
    });

    test('longer than their content length fail and cancel', () async {
      final request = http.StreamedRequest('PUT', _url)..contentLength = 2;
      request.sink
        ..add([1, 2, 3])
        ..close();
      native.onOpen = (exchange) => exchange.want(5);

      await expectLater(
        client.send(request),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('Content size exceeds specified contentLength'),
          ),
        ),
      );
      expect(native.last.cancelled, isTrue);
    });

    test('get no write after a cancel during a pending pull', () async {
      final abort = Completer<void>();
      final request = http.AbortableRequest(
        'PUT',
        _url,
        abortTrigger: abort.future,
      )..bodyBytes = [1, 2];
      final sent = client.send(request);
      await pumpEventQueue();
      expect(native.last.pendingPulls, 1);

      abort.complete();
      await expectLater(sent, throwsA(isA<http.RequestAbortedException>()));
      await pumpEventQueue();

      expect(native.last.writes, isEmpty);
      expect(native.last.cancelled, isTrue);
    });
  });

  group('cancelling', () {
    test(
      'an abort trigger that completes with an error still aborts',
      () async {
        final abort = Completer<void>();
        final sent = client.send(
          http.AbortableRequest('GET', _url, abortTrigger: abort.future),
        );
        await pumpEventQueue();

        abort.completeError(StateError('gone'));

        await expectLater(sent, throwsA(isA<http.RequestAbortedException>()));
        expect(native.last.cancelled, isTrue);
      },
    );

    test('close during a redirect aborts the next hop', () async {
      native.onOpen = (exchange) {
        if (exchange.request.url == _url) {
          exchange.answerHead(
            302,
            headers: {
              'location': ['https://example.org/next'],
            },
          );
        }
      };
      final sent = client.get(_url);
      await pumpEventQueue();
      expect(native.exchanges, hasLength(2));

      client.close();

      await expectLater(sent, throwsA(isA<http.RequestAbortedException>()));
      expect(native.last.cancelled, isTrue);
    });

    test('an abort before the head cancels and throws', () async {
      final abort = Completer<void>();
      final sent = client.send(
        http.AbortableRequest('GET', _url, abortTrigger: abort.future),
      );
      await pumpEventQueue();

      abort.complete();

      await expectLater(sent, throwsA(isA<http.RequestAbortedException>()));
      expect(native.last.cancelled, isTrue);
    });

    test('an abort mid-body cancels and errors the body', () async {
      final abort = Completer<void>();
      native.onOpen = (exchange) {
        exchange.answerHead(200);
        exchange.sendChunk([1]);
      };
      final response = await client.send(
        http.AbortableRequest('GET', _url, abortTrigger: abort.future),
      );
      final body = response.stream.toBytes();
      await pumpEventQueue();

      abort.complete();

      await expectLater(body, throwsA(isA<http.RequestAbortedException>()));
      expect(native.last.cancelled, isTrue);
    });

    test('cancelling the body subscription cancels natively', () async {
      native.onOpen = (exchange) {
        exchange.answerHead(200);
        exchange.sendChunk([1]);
      };
      final response = await client.send(http.Request('GET', _url));
      final subscription = response.stream.listen((_) {});
      await pumpEventQueue();

      await subscription.cancel();
      await pumpEventQueue();

      expect(native.last.cancelled, isTrue);
    });

    test('close cancels this client\'s requests and no others', () async {
      final other = ZunoHttpClient(
        userAgent: agent,
        deadlines: serviceDeadlines,
        native: native,
      );
      final mine = client.get(_url);
      final theirs = other.get(_url);
      await pumpEventQueue();
      final [myExchange, theirExchange] = native.exchanges.values.toList();

      client.close();

      await expectLater(mine, throwsA(isA<http.RequestAbortedException>()));
      expect(myExchange.cancelled, isTrue);
      expect(theirExchange.cancelled, isFalse);
      theirExchange
        ..answerHead(200)
        ..endBody();
      await theirs;
    });

    test('a closed client refuses new requests', () async {
      client.close();

      await expectLater(
        client.get(_url),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
      expect(native.opened, isEmpty);
    });

    test('a body nobody listens to is cancelled after the limit', () {
      fakeAsync((async) {
        native.onOpen = (exchange) => exchange.answerHead(200);
        late http.StreamedResponse response;
        client.send(http.Request('GET', _url)).then((r) => response = r);
        async.flushMicrotasks();

        async.elapse(unlistenedBodyLimit - const Duration(seconds: 1));
        expect(native.last.cancelled, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(native.last.cancelled, isTrue);

        Object? error;
        response.stream.listen((_) {}, onError: (Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isA<NativeHttpException>());
      });
    });

    test('a body listened to in time is not cancelled', () {
      leftOpenOnPurpose = true;
      fakeAsync((async) {
        client = ZunoHttpClient(
          userAgent: agent,
          deadlines: matrixDeadlines,
          native: native,
        );
        native.onOpen = (exchange) => exchange.answerHead(200);
        late http.StreamedResponse response;
        client.send(http.Request('GET', _url)).then((r) => response = r);
        async.flushMicrotasks();

        async.elapse(unlistenedBodyLimit - const Duration(seconds: 1));
        response.stream.listen((_) {});
        async.elapse(const Duration(minutes: 5));

        expect(native.last.cancelled, isFalse);
      });
    });
  });
}

class _RewindableRequest extends http.BaseRequest implements RewindableBody {
  _RewindableRequest(Uri url, this._bytes) : super('PUT', url) {
    contentLength = _bytes.length;
  }

  final List<int> _bytes;
  var rewinds = 0;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream.fromBytes(_bytes);
  }

  @override
  Stream<List<int>> rewoundBody() {
    rewinds++;
    return Stream.value(_bytes);
  }
}

class _SourceRequest extends http.BaseRequest with http.Abortable {
  _SourceRequest(Uri url, {int? length, this.abortTrigger})
    : super('POST', url) {
    contentLength = length;
  }

  @override
  final Future<void>? abortTrigger;

  var listened = false;
  var cancelled = false;

  late final _source = StreamController<List<int>>(
    onListen: () => listened = true,
    onCancel: () => cancelled = true,
  );

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_source.stream);
  }
}
