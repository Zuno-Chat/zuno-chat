import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno_http/zuno_http.dart';

import 'support/expectations.dart';

const _http = MethodChannel('zuno/http');
const _webSocket = MethodChannel('zuno/websocket');

NativeRequest _get(int id, {String url = 'https://example.org/a'}) =>
    NativeRequest(
      id: id,
      method: 'GET',
      url: Uri.parse(url),
      headers: const {},
      hasBody: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void answer(
    MethodChannel channel,
    Future<Object?> Function(MethodCall call) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  Future<Object?> Function(MethodCall) failing(
    String code, [
    Object? details,
  ]) =>
      (_) async => throw PlatformException(
        code: code,
        message: 'detail',
        details: details,
      );

  setUp(calls.clear);

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_http, null);
    messenger.setMockMethodCallHandler(_webSocket, null);
  });

  test('a native failure surfaces as a client exception of its kind', () async {
    answer(_http, failing('dns'));

    await expectLater(
      ChannelNativeHttp.instance.open(_get(1)),
      throwsA(
        allOf(
          failsAs(HttpFailureKind.dns),
          isA<http.ClientException>()
              .having((e) => e.message, 'message', 'detail')
              .having((e) => e.uri, 'uri', Uri.parse('https://example.org/a')),
        ),
      ),
    );
  });

  test(
    'an unknown native code is a protocol failure naming the code',
    () async {
      answer(_http, failing('somethingNew'));

      await expectLater(
        ChannelNativeHttp.instance.open(_get(1)),
        throwsA(
          allOf(
            failsAs(HttpFailureKind.protocol),
            isA<http.ClientException>().having(
              (e) => e.message,
              'message',
              'somethingNew: detail',
            ),
          ),
        ),
      );
    },
  );

  test('a native cleartext refusal is the same refusal Dart throws', () async {
    answer(_http, failing('cleartext'));

    await expectLater(
      ChannelNativeHttp.instance.open(_get(1, url: 'https://example.org/b')),
      throwsA(
        isA<CleartextRefusedException>().having(
          (e) => e.uri,
          'uri',
          Uri.parse('https://example.org/b'),
        ),
      ),
    );
  });

  test('open sends the request and decodes the head', () async {
    answer(
      _http,
      (_) async => {
        'status': 200,
        'reason': 'OK',
        'headers': {
          'content-type': ['application/json'],
          'link': ['<a>', '<b>'],
        },
      },
    );

    final head = await ChannelNativeHttp.instance.open(
      NativeRequest(
        id: 7,
        method: 'POST',
        url: Uri.parse('https://example.org/a?b=c'),
        headers: const {'content-type': 'application/json'},
        bodyLength: 12,
        hasBody: true,
      ),
    );

    expect(head.status, 200);
    expect(head.reason, 'OK');
    expect(head.headers['link'], ['<a>', '<b>']);
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, {
      'id': 7,
      'method': 'POST',
      'url': 'https://example.org/a?b=c',
      'headers': {'content-type': 'application/json'},
      'bodyLength': 12,
      'hasBody': true,
    });
  });

  test('a malformed head is a protocol failure', () async {
    answer(_http, (_) async => {'status': 'two hundred', 'headers': {}});

    await expectLater(
      ChannelNativeHttp.instance.open(_get(8)),
      throwsA(failsAs(HttpFailureKind.protocol)),
    );
  });

  test('an engine that failed to start fails ready and open alike', () async {
    answer(_http, failing('engineUnavailable'));

    await expectLater(
      ChannelNativeHttp.instance.ready(),
      throwsA(isA<NativeEngineUnavailable>()),
    );
    await expectLater(
      ChannelNativeHttp.instance.open(_get(2)),
      throwsA(
        isA<NativeEngineUnavailable>().having(
          (e) => e.detail,
          'detail',
          'detail',
        ),
      ),
    );
  });

  test('read decodes data, data with the end, and the bare end', () async {
    var reads = 0;
    answer(
      _http,
      (_) async => switch (reads++) {
        0 => Uint8List.fromList([1, 2, 3]),
        1 => {
          'bytes': Uint8List.fromList([4]),
          'end': true,
          'protocol': 'h3',
        },
        _ => {'end': true, 'protocol': 'h2'},
      },
    );

    final data = await ChannelNativeHttp.instance.read(3);
    final last = await ChannelNativeHttp.instance.read(3);
    final bare = await ChannelNativeHttp.instance.read(3);

    expect(data.bytes, [1, 2, 3]);
    expect(data.end, isFalse);
    expect(last.bytes, [4]);
    expect((last.end, last.protocol), (true, 'h3'));
    expect(bare.bytes, isNull);
    expect((bare.end, bare.protocol), (true, 'h2'));
  });

  test('pullBody decodes a want, a rewind and the end of asking', () async {
    var pulls = 0;
    answer(
      _http,
      (_) async => switch (pulls++) {
        0 => {'want': 65536},
        1 => {'rewind': true},
        _ => {'done': true},
      },
    );

    expect(
      await ChannelNativeHttp.instance.pullBody(4),
      isA<WantBytes>().having((p) => p.max, 'max', 65536),
    );
    expect(await ChannelNativeHttp.instance.pullBody(4), isA<Rewind>());
    expect(await ChannelNativeHttp.instance.pullBody(4), isA<BodyDone>());
  });

  test('status decodes the native phase', () async {
    answer(_http, (_) async => 'connecting');

    expect(await ChannelNativeHttp.instance.status(5), NativePhase.connecting);
  });

  test('write passes the chunk and answers with the next pull', () async {
    answer(_http, (_) async => {'want': 1024});

    final next = await ChannelNativeHttp.instance.write(
      6,
      Uint8List.fromList([9]),
      last: true,
    );

    expect(next, isA<WantBytes>().having((p) => p.max, 'max', 1024));
    expect(calls.single.method, 'write');
    expect(calls.single.arguments, {
      'id': 6,
      'chunk': Uint8List.fromList([9]),
      'last': true,
    });
  });

  test('a refused upgrade carries its HTTP status', () async {
    answer(_webSocket, failing('upgrade', 401));

    await expectLater(
      ChannelNativeWebSocket.instance.connect(
        1,
        Uri.parse('wss://sfu.example.org/rtc'),
        const {},
      ),
      throwsA(
        isA<WebSocketUpgradeRefused>().having((e) => e.status, 'status', 401),
      ),
    );
  });

  test('receive decodes a frame and a closed socket', () async {
    var receives = 0;
    answer(
      _webSocket,
      (_) async => receives++ == 0 ? Uint8List.fromList([4, 5]) : null,
    );

    expect(await ChannelNativeWebSocket.instance.receive(1), [4, 5]);
    expect(await ChannelNativeWebSocket.instance.receive(1), isNull);
  });
}
