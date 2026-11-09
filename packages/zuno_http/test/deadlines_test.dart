import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno_http/testing.dart';
import 'package:zuno_http/zuno_http.dart';

import 'support/expectations.dart';

final _url = Uri.parse('https://example.org/_matrix/client/v3/sync');

void main() {
  late ScriptedNativeHttp native;

  setUp(() => native = ScriptedNativeHttp());

  ZunoHttpClient clientWith(HttpDeadlines deadlines) =>
      ZunoHttpClient(userAgent: agent, deadlines: deadlines, native: native);

  group('connect', () {
    test('a request still connecting at 10 s is cancelled', () {
      fakeAsync((async) {
        native.onOpen = (exchange) => exchange.phase = NativePhase.connecting;
        Object? error;
        clientWith(matrixDeadlines)
            .get(_url)
            .then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(seconds: 9));
        expect(native.statusAsked, isEmpty);
        async.elapse(const Duration(seconds: 1));

        expect(native.statusAsked, [native.last.id]);
        expect(native.last.cancelled, isTrue);
        expect(error, failsAs(HttpFailureKind.connectTimedOut));
      });
    });

    test('a request waiting for its answer at 10 s runs on', () {
      fakeAsync((async) {
        http.Response? response;
        clientWith(matrixDeadlines).get(_url).then((r) => response = r);

        async.elapse(const Duration(seconds: 11));
        expect(native.last.cancelled, isFalse);
        native.last
          ..answerHead(200)
          ..endBody();
        async.flushMicrotasks();

        expect(response?.statusCode, 200);
      });
    });

    test('a request whose phase is unknown runs on', () {
      fakeAsync((async) {
        native.onOpen = (exchange) => exchange.phase = NativePhase.unknown;
        clientWith(matrixDeadlines).get(_url).ignore();

        async.elapse(const Duration(minutes: 2));

        expect(native.statusAsked, hasLength(1));
        expect(native.last.cancelled, isFalse);
      });
    });
  });

  group('think time', () {
    test('a service request with no answer by 30 s times out', () {
      fakeAsync((async) {
        Object? error;
        clientWith(serviceDeadlines)
            .get(_url)
            .then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(seconds: 29));
        expect(native.last.cancelled, isFalse);
        async.elapse(const Duration(seconds: 1));

        expect(native.last.cancelled, isTrue);
        expect(error, failsAs(HttpFailureKind.timedOut));
      });
    });

    test('a Matrix request waits as long as the server thinks', () {
      fakeAsync((async) {
        clientWith(matrixDeadlines).get(_url).ignore();

        async.elapse(const Duration(minutes: 10));

        expect(native.last.cancelled, isFalse);
      });
    });

    test('a request with its own think time times out then', () {
      fakeAsync((async) {
        Object? error;
        clientWith(matrixDeadlines)
            .send(
              DeadlineRequest(
                'GET',
                _url,
                thinkTime: const Duration(seconds: 40),
              ),
            )
            .then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(seconds: 39));
        expect(native.last.cancelled, isFalse);
        async.elapse(const Duration(seconds: 1));

        expect(error, failsAs(HttpFailureKind.timedOut));
      });
    });

    test('a request with its own think time is still abortable', () {
      fakeAsync((async) {
        final abort = Completer<void>();
        Object? error;
        clientWith(matrixDeadlines)
            .send(
              DeadlineRequest(
                'GET',
                _url,
                abortTrigger: abort.future,
                thinkTime: const Duration(seconds: 40),
              ),
            )
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.flushMicrotasks();

        abort.complete();
        async.flushMicrotasks();

        expect(error, isA<http.RequestAbortedException>());
      });
    });

    test('an upload in progress is not cut by think time', () {
      fakeAsync((async) {
        final request = http.Request('POST', _url)
          ..bodyBytes = List.filled(50, 1);
        http.StreamedResponse? response;
        clientWith(serviceDeadlines).send(request).then((r) => response = r);
        async.flushMicrotasks();

        for (var i = 0; i < 5; i++) {
          async.elapse(const Duration(seconds: 20));
          native.last.want(10);
          async.flushMicrotasks();
        }
        native.last.answerHead(200);
        async.flushMicrotasks();

        expect(native.last.cancelled, isFalse);
        expect(response?.statusCode, 200);
      });
    });

    test(
      'an upload chunk sent after the answer does not restart think time',
      () {
        fakeAsync((async) {
          final request = http.Request('POST', _url)
            ..bodyBytes = List.filled(50, 1);
          late http.StreamedResponse response;
          clientWith(serviceDeadlines).send(request).then((r) => response = r);
          async.flushMicrotasks();
          native.last.want(10);
          async.flushMicrotasks();
          native.last.answerHead(200, endsUpload: false);
          async.flushMicrotasks();
          Object? error;
          response.stream.listen((_) {}, onError: (Object e) => error = e);

          native.last.want(10);
          async.flushMicrotasks();
          for (var i = 0; i < 3; i++) {
            async.elapse(const Duration(seconds: 20));
            native.last.sendChunk([i]);
            async.flushMicrotasks();
          }

          expect(native.last.writes, hasLength(2));
          expect(error, isNull);
          expect(native.last.cancelled, isFalse);
        });
      },
    );

    test(
      'a redirect whose think time ran out as it arrived is not followed',
      () {
        fakeAsync((async) {
          native.onOpen = (exchange) => exchange.headAlreadySent = true;
          Object? error;
          clientWith(serviceDeadlines)
              .get(_url)
              .then<void>((_) {}, onError: (Object e) => error = e);
          async.elapse(const Duration(seconds: 30));

          native.last.answerHead(
            302,
            headers: {
              'location': ['https://example.org/next'],
            },
          );
          async.flushMicrotasks();

          expect(error, failsAs(HttpFailureKind.timedOut));
          expect(native.opened, hasLength(1));
        });
      },
    );

    test('an upload that stops moving times out', () {
      fakeAsync((async) {
        final request = http.Request('POST', _url)
          ..bodyBytes = List.filled(50, 1);
        Object? error;
        clientWith(serviceDeadlines)
            .send(request)
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.flushMicrotasks();
        native.last.want(10);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));

        expect(error, failsAs(HttpFailureKind.timedOut));
      });
    });
  });

  group('idle', () {
    test('a service body silent for 30 s times out', () {
      fakeAsync((async) {
        native.onOpen = (exchange) {
          exchange.answerHead(200);
          exchange.sendChunk([1]);
        };
        late http.StreamedResponse response;
        clientWith(serviceDeadlines)
            .send(http.Request('GET', _url))
            .then((r) => response = r);
        async.flushMicrotasks();
        Object? error;
        response.stream.listen((_) {}, onError: (Object e) => error = e);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 29));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 1));

        expect(error, failsAs(HttpFailureKind.timedOut));
        expect(native.last.cancelled, isTrue);
      });
    });

    test('each chunk restarts the service idle limit', () {
      fakeAsync((async) {
        native.onOpen = (exchange) => exchange.answerHead(200);
        late http.StreamedResponse response;
        clientWith(serviceDeadlines)
            .send(http.Request('GET', _url))
            .then((r) => response = r);
        async.flushMicrotasks();
        Object? error;
        response.stream.listen((_) {}, onError: (Object e) => error = e);

        for (var i = 0; i < 4; i++) {
          async.elapse(const Duration(seconds: 20));
          native.last.sendChunk([i]);
          async.flushMicrotasks();
        }

        expect(error, isNull);
      });
    });

    test('a paused listener is not cut by the idle limit', () {
      fakeAsync((async) {
        native.onOpen = (exchange) {
          exchange.answerHead(200);
          exchange.sendChunk([1]);
        };
        late http.StreamedResponse response;
        clientWith(serviceDeadlines)
            .send(http.Request('GET', _url))
            .then((r) => response = r);
        async.flushMicrotasks();
        Object? error;
        late StreamSubscription<List<int>> subscription;
        subscription = response.stream.listen(
          (_) => subscription.pause(),
          onError: (Object e) => error = e,
        );
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 2));
        expect(error, isNull);
        expect(native.last.cancelled, isFalse);

        subscription.resume();
        async.elapse(const Duration(seconds: 30));
        expect(error, failsAs(HttpFailureKind.timedOut));
      });
    });

    test('a Matrix body has no idle limit', () {
      fakeAsync((async) {
        native.onOpen = (exchange) => exchange.answerHead(200);
        late http.StreamedResponse response;
        clientWith(matrixDeadlines)
            .send(http.Request('GET', _url))
            .then((r) => response = r);
        async.flushMicrotasks();
        Object? error;
        response.stream.listen((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(minutes: 10));

        expect(error, isNull);
        expect(native.last.cancelled, isFalse);
      });
    });
  });
}
