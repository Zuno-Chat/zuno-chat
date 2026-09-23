import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/registration_code_request.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  test('the code endpoint is the zuno_register module on the homeserver', () {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org:8448');

    expect(
      registrationCodeUri(client).toString(),
      'https://example.org:8448/_synapse/client/zuno/register/token',
    );
  });

  test('no homeserver means no endpoint', () {
    expect(registrationCodeUri(buildTestClient()), isNull);
  });

  test('the address is posted as JSON', () async {
    late http.Request sent;
    final client = buildTestClient(
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response('{}', 202);
      }),
    )..homeserver = Uri.parse('https://example.org');

    final outcome = await requestRegistrationCode(client, ' alex@example.org ');

    expect(outcome, RegistrationCodeOutcome.sent);
    expect(sent.url.path, '/_synapse/client/zuno/register/token');
    expect(jsonDecode(sent.body), {'email': 'alex@example.org'});
  });

  test('every status maps to an outcome', () {
    expect(registrationCodeOutcomeFrom(202), RegistrationCodeOutcome.sent);
    expect(
      registrationCodeOutcomeFrom(400),
      RegistrationCodeOutcome.invalidEmail,
    );
    expect(
      registrationCodeOutcomeFrom(413),
      RegistrationCodeOutcome.invalidEmail,
    );
    expect(
      registrationCodeOutcomeFrom(404),
      RegistrationCodeOutcome.unavailable,
    );
    expect(
      registrationCodeOutcomeFrom(503),
      RegistrationCodeOutcome.unavailable,
    );
    expect(
      registrationCodeOutcomeFrom(429),
      RegistrationCodeOutcome.rateLimited,
    );
    expect(
      registrationCodeOutcomeFrom(502),
      RegistrationCodeOutcome.serverError,
    );
  });

  test('an unreachable homeserver reads as offline', () async {
    final client = buildTestClient(
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    )..homeserver = Uri.parse('https://example.org');

    expect(
      await requestRegistrationCode(client, 'alex@example.org'),
      RegistrationCodeOutcome.offline,
    );
  });

  test('every way a connection fails reads as offline', () async {
    for (final failure in <Object>[
      const SocketException('no route'),
      const HandshakeException('captive portal'),
      TimeoutException('slow'),
    ]) {
      final client = buildTestClient(
        httpClient: MockClient((_) async => throw failure),
      )..homeserver = Uri.parse('https://example.org');

      expect(
        await requestRegistrationCode(client, 'alex@example.org'),
        RegistrationCodeOutcome.offline,
        reason: '$failure',
      );
    }
  });

  test('a homeserver that never answers reads as offline', () {
    fakeAsync((async) {
      final client = buildTestClient(
        httpClient: MockClient((_) => Completer<http.Response>().future),
      )..homeserver = Uri.parse('https://example.org');

      RegistrationCodeOutcome? outcome;
      requestRegistrationCode(
        client,
        'alex@example.org',
      ).then((value) => outcome = value);
      async.elapse(registrationCodeTimeout);

      expect(outcome, RegistrationCodeOutcome.offline);
    });
  });

  group('looksLikeEmail', () {
    test('accepts an ordinary address', () {
      expect(looksLikeEmail(' alex@example.org '), isTrue);
    });

    test('rejects what cannot be an address', () {
      expect(looksLikeEmail('alex'), isFalse);
      expect(looksLikeEmail('alex@example'), isFalse);
      expect(looksLikeEmail('alex@@example.org'), isFalse);
      expect(looksLikeEmail('@example.org'), isFalse);
      expect(looksLikeEmail('alex@ example.org'), isFalse);
      expect(looksLikeEmail('alex@example.'), isFalse);
    });
  });
}
