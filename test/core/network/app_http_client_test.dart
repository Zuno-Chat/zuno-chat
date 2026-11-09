import 'dart:io' show HttpOverrides;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/network/app_http_client.dart';
import 'package:zuno/core/network/app_http_overrides.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno_http/testing.dart';
import 'package:zuno_http/zuno_http.dart';

import '../../helpers/caught_reports.dart';

final _url = Uri.parse('https://example.org/_matrix/client/versions');

void main() {
  late ScriptedNativeHttp native;

  setUp(() {
    native = ScriptedNativeHttp();
    forgetNetworkEngineReadyForTest();
  });

  Object? outcomeOf(FakeAsync async, HttpClientKind kind, Duration wait) {
    Object? outcome;
    nativeHttpClient(kind, native: native)
        .get(_url)
        .then<void>(
          (_) => outcome = 'answered',
          onError: (Object e) => outcome = e,
        );
    async.elapse(wait);
    return outcome;
  }

  test('a Matrix client waits as long as the server thinks', () {
    fakeAsync((async) {
      expect(
        outcomeOf(async, HttpClientKind.matrix, const Duration(minutes: 10)),
        isNull,
      );
    });
  });

  test('a service client gives up after 30 s with no answer', () {
    fakeAsync((async) {
      expect(
        outcomeOf(async, HttpClientKind.service, const Duration(seconds: 29)),
        isNull,
      );
      async.elapse(const Duration(seconds: 1));

      expect(native.last.cancelled, isTrue);
    });
  });

  test(
    'every client sends the installed app version as its User-Agent',
    () async {
      final previous = HttpOverrides.current;
      addTearDown(() => HttpOverrides.global = previous);
      await installAppHttpOverrides(
        version: () async => '1.2.0',
        platform: AppPlatform.android,
      );
      native.onOpen = (exchange) => exchange
        ..answerHead(200)
        ..endBody();

      await nativeHttpClient(HttpClientKind.service, native: native).get(_url);

      expect(
        native.last.request.headers['user-agent'],
        'Zuno/1.2.0 (Android; im.zuno.chat)',
      );
    },
  );

  test('a network engine that failed to start is reported once', () async {
    native.readyFailure = const NativeEngineUnavailable('UnsatisfiedLinkError');

    final reports = await reportsDuring(() async {
      nativeHttpClient(HttpClientKind.matrix, native: native);
      nativeHttpClient(HttpClientKind.service, native: native);
      await pumpEventQueue();
    });

    expect(reports, ['start the network engine']);
    expect(native.readyCalls, 1);
  });

  test('tests get stand-ins, never the native client or socket', () async {
    expect(appHttpClient(HttpClientKind.service), isNot(isA<ZunoHttpClient>()));
    await expectLater(
      appWebSocket(Uri.parse('wss://sfu.example.org/rtc'), const {}),
      throwsA(isA<NativeHttpException>()),
    );
  });
}
