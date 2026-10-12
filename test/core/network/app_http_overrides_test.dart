import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:zuno/core/network/app_http_overrides.dart';
import 'package:zuno/core/platform/app_platform.dart';

const _agent = 'Zuno/1.2.0 (Android; im.zuno.chat)';

void main() {
  tearDown(() => HttpOverrides.global = null);

  test('names the app, its version and its package', () {
    expect(zunoUserAgent('1.2.0'), _agent);
  });

  test('names iOS on an iPhone', () {
    expect(
      zunoUserAgent('1.2.0', platform: AppPlatform.ios),
      'Zuno/1.2.0 (iOS; im.zuno.chat)',
    );
  });

  test(
    'every HTTP client created after install on an iPhone names iOS',
    () async {
      await installAppHttpOverrides(
        version: () async => '1.2.0',
        platform: AppPlatform.ios,
      );

      expect(HttpClient().userAgent, 'Zuno/1.2.0 (iOS; im.zuno.chat)');
    },
  );

  test('reads the version from the installed package by default', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Zuno',
      packageName: 'im.zuno.chat',
      version: '1.2.0',
      buildNumber: '2',
      buildSignature: '',
    );

    await installAppHttpOverrides();

    expect(HttpClient().userAgent, _agent);
  });

  test('still names the app when the version cannot be read', () async {
    await installAppHttpOverrides(
      version: () async => throw MissingPluginException('no plugin'),
    );

    expect(HttpClient().userAgent, 'Zuno (Android; im.zuno.chat)');
  });

  test('is readable by code that sets the header itself', () async {
    await installAppHttpOverrides(version: () async => '1.2.0');

    expect(appUserAgent, _agent);
  });

  test('is unknown before install', () {
    expect(appUserAgent, isNull);
  });

  group('cleartext', () {
    late ServerSocket listener;
    late int accepted;
    late Completer<List<int>> firstBytes;

    setUp(() async {
      await installAppHttpOverrides(version: () async => '1.2.0');
      accepted = 0;
      firstBytes = Completer();
      listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      listener.listen((socket) {
        accepted++;
        socket.first
            .then<void>(firstBytes.complete, onError: (_) {})
            .whenComplete(socket.destroy);
      });
      addTearDown(listener.close);
    });

    HttpClient client({bool viaProxy = false}) {
      final client = HttpClient();
      if (viaProxy) {
        client.findProxy = (_) => 'PROXY 127.0.0.1:${listener.port}';
      }
      addTearDown(() => client.close(force: true));
      return client;
    }

    void send(HttpClient client, String url) => unawaited(
      client.getUrl(Uri.parse(url)).then<void>((_) {}, onError: (_) {}),
    );

    test('an http address is refused before anything connects', () async {
      await expectLater(
        client().getUrl(Uri.parse('http://127.0.0.1:${listener.port}/')),
        throwsA(isA<CleartextRefusedException>()),
      );
      await pumpEventQueue();

      expect(accepted, 0);
    });

    test('an http address through a proxy is refused too', () async {
      await expectLater(
        client(viaProxy: true).getUrl(Uri.parse('http://zuno.example/')),
        throwsA(isA<CleartextRefusedException>()),
      );
      await pumpEventQueue();

      expect(accepted, 0);
    });

    test('an https address speaks TLS from the first byte', () async {
      send(client(), 'https://127.0.0.1:${listener.port}/');

      expect((await firstBytes.future).first, 0x16);
    });

    test('an https address through a proxy opens a tunnel first', () async {
      send(client(viaProxy: true), 'https://zuno.example/');

      expect(
        ascii.decode(await firstBytes.future),
        startsWith('CONNECT zuno.example:443 HTTP/1.1'),
      );
    });

    test('a refusal names the host, never the path or query', () {
      final refusal = CleartextRefusedException(
        Uri.parse('http://zuno.example/_matrix/sync?access_token=syt_secret'),
      );

      expect('$refusal', contains('zuno.example'));
      expect('$refusal', isNot(contains('access_token')));
      expect('$refusal', isNot(contains('_matrix')));
    });
  });
}
