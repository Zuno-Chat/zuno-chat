import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_http/zuno_http.dart';

void main() {
  test('refuses http to an IP address', () {
    expect(
      cleartextRefusal(
        Uri.parse('http://192.168.1.2/x'),
        secureScheme: 'https',
      ),
      isA<CleartextRefusedException>().having(
        (e) => e.uri.host,
        'host',
        '192.168.1.2',
      ),
    );
  });

  test('lets https through', () {
    expect(
      cleartextRefusal(
        Uri.parse('https://example.org/x'),
        secureScheme: 'https',
      ),
      isNull,
    );
  });

  test('refuses ws when wss is required', () {
    expect(
      cleartextRefusal(Uri.parse('ws://example.org/rtc'), secureScheme: 'wss'),
      isA<CleartextRefusedException>(),
    );
  });

  test('names the refused scheme and host', () {
    expect(
      CleartextRefusedException(Uri.parse('http://example.org/a')).toString(),
      'CleartextRefusedException: refused http://example.org',
    );
  });
}
