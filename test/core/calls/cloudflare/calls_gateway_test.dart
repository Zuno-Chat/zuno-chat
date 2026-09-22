import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/calls_gateway.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  test('SFU and TURN roots hang off the homeserver host', () {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org');

    expect(callsGatewayBaseUri(client).toString(), 'https://example.org/calls');
    expect(
      turnCredentialsUri(client).toString(),
      'https://example.org/turn/credentials',
    );
  });

  test('a non-default port is carried through', () {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org:8448');

    expect(
      callsGatewayBaseUri(client).toString(),
      'https://example.org:8448/calls',
    );
  });

  test("a homeserver served under a path prefix doesn't leak it into the gateway URL", () {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org/matrix');

    expect(callsGatewayBaseUri(client).toString(), 'https://example.org/calls');
  });

  test('throws rather than guessing when no homeserver is set', () {
    expect(() => callsGatewayBaseUri(buildTestClient()), throwsStateError);
  });
}
