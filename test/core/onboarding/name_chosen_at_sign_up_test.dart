import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/http/typed_server_answers.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  Client clientAnswering(FakeHttpHandler answer) =>
      buildTestClient(
          userId: '@alex:example.org',
          httpClient: FakeHttpClient(answer),
        )
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'token';

  Future<(bool, List<String>)> readWith(FakeHttpHandler answer) async {
    late bool chosen;
    final reports = await reportsDuring(() async {
      chosen = await nameChosenAtSignUp(clientAnswering(answer));
    });
    return (chosen, reports);
  }

  test('a name set at sign-up counts', () async {
    final (chosen, reports) = await readWith(
      (_) async =>
          http.Response(jsonEncode({'displayname': 'Alex Smith'}), 200),
    );

    expect(chosen, isTrue);
    expect(reports, isEmpty);
  });

  test('the bare username does not', () async {
    final (chosen, _) = await readWith(
      (_) async => http.Response(jsonEncode({'displayname': 'alex'}), 200),
    );

    expect(chosen, isFalse);
  });

  test('no connection asks for the name, with no report', () async {
    final (chosen, reports) = await readWith(
      (_) async => throw http.ClientException('offline'),
    );

    expect(chosen, isFalse);
    expect(reports, isEmpty);
  });

  test('a server error page asks for the name, with no report', () async {
    final (chosen, reports) = await readWith(
      (_) async => throw const ServerAnswerFailed(502),
    );

    expect(chosen, isFalse);
    expect(reports, isEmpty);
  });

  test('an unexpected failure asks for the name and is reported', () async {
    final (chosen, reports) = await readWith(
      (_) async => throw StateError('broken'),
    );

    expect(chosen, isFalse);
    expect(reports, ['read the chosen name']);
  });

  test('a server that never answers asks for the name after a while', () {
    fakeAsync((async) {
      bool? chosen;
      unawaited(
        nameChosenAtSignUp(
          clientAnswering((_) => Completer<http.Response>().future),
        ).then((value) => chosen = value),
      );

      async.elapse(const Duration(seconds: 7));
      expect(chosen, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(chosen, isFalse);
    });
  });
}
