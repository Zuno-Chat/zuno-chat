import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno_http/src/redirects.dart';
import 'package:zuno_http/testing.dart';
import 'package:zuno_http/zuno_http.dart';

import 'support/expectations.dart';

final _start = Uri.parse('https://example.org/a');

const _sensitive = {
  'authorization': 'Bearer t',
  'www-authenticate': 'Basic',
  'proxy-authorization': 'Basic p',
  'proxy-authenticate': 'Basic',
  'cookie': 'c=1',
  'cookie2': 'c=2',
};

void main() {
  group('followsRedirect', () {
    test('GET and HEAD follow 301, 302, 303, 307 and 308', () {
      for (final method in ['GET', 'HEAD']) {
        for (final status in [301, 302, 303, 307, 308]) {
          expect(
            followsRedirect(method, status),
            isTrue,
            reason: '$method $status',
          );
        }
        for (final status in [300, 304, 305, 200]) {
          expect(
            followsRedirect(method, status),
            isFalse,
            reason: '$method $status',
          );
        }
      }
    });

    test('POST follows only 303', () {
      expect(followsRedirect('POST', 303), isTrue);
      for (final status in [301, 302, 307, 308]) {
        expect(followsRedirect('POST', status), isFalse, reason: '$status');
      }
    });

    test('other methods never follow', () {
      expect(followsRedirect('PUT', 303), isFalse);
      expect(followsRedirect('DELETE', 302), isFalse);
    });
  });

  group('redirectHeaders', () {
    final plain = {'accept': 'application/json', 'content-type': 'text/plain'};

    test('keep every header on the same origin', () {
      expect(
        redirectHeaders(
          Uri.parse('https://example.org/a'),
          Uri.parse('https://example.org:443/b'),
          {..._sensitive, ...plain},
        ),
        {..._sensitive, ...plain},
      );
    });

    test('drop the sensitive six when the port changes', () {
      expect(
        redirectHeaders(
          Uri.parse('https://example.org/a'),
          Uri.parse('https://example.org:8443/b'),
          {..._sensitive, ...plain},
        ),
        plain,
      );
    });

    test('drop the sensitive six when the host changes', () {
      expect(
        redirectHeaders(
          Uri.parse('https://example.org/a'),
          Uri.parse('https://cdn.example.net/b'),
          {'Authorization': 'Bearer t', 'Cookie': 'c=1', ...plain},
        ),
        plain,
      );
    });
  });

  group('the client', () {
    late ScriptedNativeHttp native;
    late ZunoHttpClient client;

    setUp(() {
      native = ScriptedNativeHttp();
      client = ZunoHttpClient(
        userAgent: agent,
        deadlines: serviceDeadlines,
        native: native,
      );
    });

    void route(Map<String, (int, String?)> routes, {int? want}) {
      native.onOpen = (exchange) {
        if (want != null && exchange.request.hasBody) exchange.want(want);
        final (status, location) =
            routes[exchange.request.url.toString()] ?? (200, null);
        exchange.answerHead(
          status,
          headers: {
            if (location != null) 'location': [location],
          },
        );
        exchange.sendChunk([status ~/ 100]);
        exchange.endBody();
      };
    }

    List<NativeRequest> hops() => [
      for (final exchange in native.exchanges.values) exchange.request,
    ];

    test(
      'follow a GET 302 to its location and report the raw location',
      () async {
        route({'https://example.org/a': (302, '/b')});

        final response = await client.send(http.Request('GET', _start));
        final body = await response.stream.toBytes();

        expect(body, [2]);
        expect(response.statusCode, 200);
        expect((response as http.BaseResponseWithUrl).url, Uri.parse('/b'));
        expect(hops().map((hop) => hop.url.toString()), [
          'https://example.org/a',
          'https://example.org/b',
        ]);
        expect(hops().last.method, 'GET');
        expect(native.exchanges.values.first.cancelled, isTrue);
        expect(native.allEnded, isTrue);
      },
    );

    test('resolve a relative location against the hop that sent it', () async {
      route({
        'https://example.org/a': (302, 'https://cdn.example.org/b'),
        'https://cdn.example.org/b': (302, '/c'),
      });

      await client.get(_start);

      expect(hops().map((hop) => hop.url.toString()), [
        'https://example.org/a',
        'https://cdn.example.org/b',
        'https://cdn.example.org/c',
      ]);
    });

    test('re-send a POST 303 as a GET with no body', () async {
      route({
        'https://example.org/a': (303, 'https://example.org/done'),
      }, want: 64);

      final response = await client.post(_start, body: 'payload');

      expect(response.statusCode, 200);
      expect(hops().last.method, 'GET');
      expect(hops().last.hasBody, isFalse);
      expect(hops().last.bodyLength, isNull);
      expect(native.allEnded, isTrue);
    });

    test('return a POST 302 unfollowed, as dart:io does', () async {
      route({'https://example.org/a': (302, '/b')}, want: 64);

      final response = await client.post(_start, body: 'payload');

      expect(response.statusCode, 302);
      expect(response.isRedirect, isFalse);
      expect(hops(), hasLength(1));
    });

    test('return a 3xx unfollowed when following is off', () async {
      route({'https://example.org/a': (302, '/b')});

      final response = await client.send(
        http.Request('GET', _start)..followRedirects = false,
      );
      await response.stream.drain<void>();

      expect(response.statusCode, 302);
      expect(response.isRedirect, isTrue);
      expect(hops(), hasLength(1));
    });

    test(
      'drop Authorization on a hop to another host and keep it on the same one',
      () async {
        route({
          'https://example.org/a': (307, 'https://example.org/b'),
          'https://example.org/b': (307, 'https://cdn.example.net/c'),
        });

        await client.get(_start, headers: {'Authorization': 'Bearer t'});

        final auth = [
          for (final hop in hops())
            hop.headers.entries
                .where((e) => e.key.toLowerCase() == 'authorization')
                .map((e) => e.value)
                .firstOrNull,
        ];
        expect(auth, ['Bearer t', 'Bearer t', null]);
      },
    );

    test('detect a repeated location as a loop', () async {
      route({
        'https://example.org/a': (302, 'https://example.org/b'),
        'https://example.org/b': (302, 'https://example.org/b'),
      });

      await expectLater(
        client.get(_start),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('Redirect loop detected'),
          ),
        ),
      );
      expect(native.allEnded, isTrue);
    });

    test('fail a redirect without a location', () async {
      route({'https://example.org/a': (302, null)});

      await expectLater(
        client.get(_start),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('no Location header'),
          ),
        ),
      );
      expect(native.allEnded, isTrue);
    });

    test('fail a redirect with two locations', () async {
      native.onOpen = (exchange) {
        exchange.answerHead(
          302,
          headers: {
            'location': ['https://example.org/b', 'https://example.org/c'],
          },
        );
      };

      await expectLater(
        client.get(_start),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('More than one value'),
          ),
        ),
      );
      expect(native.allEnded, isTrue);
    });

    test('fail past the redirect limit', () async {
      route({
        'https://example.org/a': (302, 'https://example.org/1'),
        'https://example.org/1': (302, 'https://example.org/2'),
        'https://example.org/2': (302, 'https://example.org/3'),
      });

      await expectLater(
        client.send(http.Request('GET', _start)..maxRedirects = 2),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('Redirect limit exceeded'),
          ),
        ),
      );
      expect(hops(), hasLength(3));
      expect(native.allEnded, isTrue);
    });

    test('refuse a redirect from https to http', () async {
      route({'https://example.org/a': (302, 'http://example.org/b')});

      await expectLater(
        client.get(_start),
        throwsA(isA<CleartextRefusedException>()),
      );
      expect(hops(), hasLength(1));
      expect(native.allEnded, isTrue);
    });
  });
}
