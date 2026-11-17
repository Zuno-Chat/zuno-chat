import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/updates/update_checks.dart';

import '../../helpers/fake_http.dart';

FakeHttpClient _answering(Object body, {List<Uri>? asked, int status = 200}) =>
    FakeHttpClient((request) async {
      asked?.add(request.url);
      return http.Response(body is String ? body : jsonEncode(body), status);
    });

void main() {
  group('checkPlay', () {
    test('offers the version Play has for this device', () {
      expect(checkPlay(1007000, packageName: 'im.zuno.chat'), (
        build: 1007000,
        link: Uri.parse(
          'https://play.google.com/store/apps/details?id=im.zuno.chat',
        ),
      ));
    });

    test('offers nothing when Play has no update to offer', () {
      expect(checkPlay(null, packageName: 'im.zuno.chat'), isNull);
    });
  });

  group('checkAppStore', () {
    const listing = 'https://apps.apple.com/gb/app/zuno/id1';

    Map<String, Object> answer({String minimumOsVersion = '18.0'}) => {
      'resultCount': 1,
      'results': [
        {
          'version': '1.7.0',
          'minimumOsVersion': minimumOsVersion,
          'trackViewUrl': listing,
        },
      ],
    };

    Future<AvailableUpdate?> check(
      FakeHttpClient client, {
      String osVersion = 'Version 18.2 (Build 22C152)',
    }) => checkAppStore(client, bundleId: 'im.zuno.chat', osVersion: osVersion);

    test('asks Apple for this app and offers the live version with its '
        'listing', () async {
      final asked = <Uri>[];
      expect(await check(_answering(answer(), asked: asked)), (
        build: 1007000,
        link: Uri.parse(listing),
      ));
      expect(asked, [
        Uri.parse('https://itunes.apple.com/lookup?bundleId=im.zuno.chat'),
      ]);
    });

    test('offers nothing when the version needs a newer iOS', () async {
      expect(await check(_answering(answer(minimumOsVersion: '26.0'))), isNull);
    });

    test('offers nothing when the device iOS version does not parse', () async {
      expect(await check(_answering(answer()), osVersion: 'unknown'), isNull);
    });

    test('offers nothing when Apple does not list the app', () async {
      expect(
        await check(_answering({'resultCount': 0, 'results': <Object>[]})),
        isNull,
      );
    });

    test('offers nothing on a failed or malformed answer', () async {
      expect(await check(_answering(answer(), status: 503)), isNull);
      expect(await check(_answering('not json')), isNull);
      expect(
        await check(
          _answering({
            'resultCount': 1,
            'results': [
              {'version': '1.7.0'},
            ],
          }),
        ),
        isNull,
      );
    });
  });

  group('checkWebsite', () {
    final download = Uri.parse('https://zuno.chat/download');

    final manifest = {
      'version': '1.7.0',
      'apk': 'zuno-1.7.0.apk',
      'sha256': 'ab' * 32,
      'size': 1,
    };

    Future<AvailableUpdate?> check(FakeHttpClient client) =>
        checkWebsite(client);

    test('reads the website manifest and offers its version', () async {
      final asked = <Uri>[];
      expect(await check(_answering(manifest, asked: asked)), (
        build: 1007000,
        link: download,
      ));
      expect(asked, [Uri.parse('https://get.zuno.chat/android/latest.json')]);
    });

    test('offers nothing on a failed or malformed answer', () async {
      expect(await check(_answering(manifest, status: 404)), isNull);
      expect(await check(_answering('{"version":')), isNull);
      expect(await check(_answering({'version': 7})), isNull);
    });
  });
}
