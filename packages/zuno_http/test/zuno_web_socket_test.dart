import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_http/zuno_http.dart';

import 'support/expectations.dart';
import 'support/scripted_native_web_socket.dart';

final _url = Uri.parse('wss://sfu.example.org/rtc?access_token=x');

void main() {
  late ScriptedNativeWebSocket native;

  setUp(() => native = ScriptedNativeWebSocket());

  Future<ZunoWebSocket> connect([Map<String, String> headers = const {}]) =>
      ZunoWebSocket.connect(
        _url,
        headers: headers,
        userAgent: agent,
        native: native,
      );

  test('refuses ws without asking native', () async {
    await expectLater(
      ZunoWebSocket.connect(
        Uri.parse('ws://sfu.example.org/rtc'),
        userAgent: agent,
        native: native,
      ),
      throwsA(isA<CleartextRefusedException>()),
    );
    expect(native.connected, isEmpty);
  });

  test(
    'sends the caller headers and the User-Agent with the upgrade',
    () async {
      await connect({'Authorization': 'Bearer t'});

      final (url, headers) = native.connected.values.single;
      expect(url, _url);
      expect(headers['Authorization'], 'Bearer t');
      expect(headers['user-agent'], agent);
    },
  );

  test('a refused upgrade carries its status', () async {
    native.connectFailure = const WebSocketUpgradeRefused(503);

    await expectLater(
      connect(),
      throwsA(
        isA<WebSocketUpgradeRefused>().having((e) => e.status, 'status', 503),
      ),
    );
  });

  test('receives only while frames are listened to', () async {
    final socket = await connect();
    await pumpEventQueue();
    expect(native.receives, 0);

    socket.frames.listen((_) {});
    await pumpEventQueue();

    expect(native.receives, 1);
  });

  test('receives no further while the listener is paused', () async {
    final socket = await connect();
    final subscription = socket.frames.listen((_) {});
    await pumpEventQueue();
    subscription.pause();
    final receivesWhenPaused = native.receives;
    native
      ..frame([1])
      ..frame([2]);
    await pumpEventQueue();

    expect(native.receives, lessThanOrEqualTo(receivesWhenPaused + 1));
    await subscription.cancel();
  });

  test('delivers frames in order and ends when the server closes', () async {
    final socket = await connect();
    native
      ..frame([1])
      ..frame([2, 3])
      ..closedByServer();

    expect(await socket.frames.toList(), [
      [1],
      [2, 3],
    ]);
  });

  test('a dropped connection errors frames as its kind', () async {
    final socket = await connect();
    native.drop(HttpFailureKind.connectionLost);

    await expectLater(
      socket.frames.toList(),
      throwsA(
        isA<NativeHttpException>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.connectionLost,
        ),
      ),
    );
  });

  test('sends frames as bytes', () async {
    final socket = await connect();

    socket.send([7, 8]);
    await pumpEventQueue();

    expect(native.sent, [
      [7, 8],
    ]);
  });

  test(
    'a send the native side refuses errors frames as a lost connection',
    () async {
      final socket = await connect();
      final frames = socket.frames.toList();
      native.sendAccepted = false;

      socket.send([1]);

      await expectLater(
        frames,
        throwsA(
          isA<NativeHttpException>().having(
            (e) => e.kind,
            'kind',
            HttpFailureKind.connectionLost,
          ),
        ),
      );
    },
  );

  test('a send that fails natively errors frames', () async {
    final socket = await connect();
    final frames = socket.frames.toList();
    native.sendFailure = NativeHttpException(
      HttpFailureKind.connectionLost,
      'gone',
    );

    socket.send([1]);

    await expectLater(
      frames,
      throwsA(
        isA<NativeHttpException>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.connectionLost,
        ),
      ),
    );
  });

  test('an upgrade that never answers times out and is closed natively', () {
    fakeAsync((async) {
      native.holdConnect = Completer<void>();
      Object? error;
      connect().then<void>((_) {}, onError: (Object e) => error = e);
      async.flushMicrotasks();

      async.elapse(webSocketConnectLimit - const Duration(seconds: 1));
      expect(error, isNull);
      async.elapse(const Duration(seconds: 1));

      expect(
        error,
        isA<NativeHttpException>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.timedOut,
        ),
      );
      expect(native.closed, native.attempted);
    });
  });

  test('sending on a closed socket throws', () async {
    final socket = await connect();
    await socket.close();

    expect(() => socket.send([1]), throwsStateError);
  });

  test('close closes natively once', () async {
    final socket = await connect();

    await socket.close();
    await socket.close();

    expect(native.closed, [native.id]);
  });

  test('cancelling the frames subscription closes the socket', () async {
    final socket = await connect();
    final subscription = socket.frames.listen((_) {});
    await pumpEventQueue();

    await subscription.cancel();
    await pumpEventQueue();

    expect(native.closed, [native.id]);
    expect(() => socket.send([1]), throwsStateError);
  });
}
