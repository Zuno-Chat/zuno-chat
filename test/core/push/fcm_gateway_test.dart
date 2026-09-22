import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm_gateway.dart';

void main() {
  test('derives the gateway from the homeserver host', () {
    expect(
      fcmGatewayUri(Uri.parse('https://matrix.example.org')),
      Uri.parse('https://matrix.example.org/_matrix/push/v1/notify'),
    );
  });

  test('keeps a non-default port', () {
    expect(
      fcmGatewayUri(Uri.parse('https://matrix.example.org:8448')),
      Uri.parse('https://matrix.example.org:8448/_matrix/push/v1/notify'),
    );
  });

  test('replaces any path the homeserver URI carries', () {
    expect(
      fcmGatewayUri(Uri.parse('https://example.org/matrix')),
      Uri.parse('https://example.org/_matrix/push/v1/notify'),
    );
  });

  test('forces https, so a homeserver reached over http never downgrades '
      'the gateway', () {
    expect(
      fcmGatewayUri(Uri.parse('http://matrix.example.org'))?.scheme,
      'https',
    );
  });

  test('returns null when the homeserver is unknown', () {
    expect(fcmGatewayUri(null), isNull);
  });
}
