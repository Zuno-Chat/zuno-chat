import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/failed_tests.dart';

void main() {
  const root = '/repo';

  String suite(int id, String path) => jsonEncode({
    'type': 'suite',
    'suite': {'id': id, 'platform': 'vm', 'path': '$root/$path'},
  });

  String start(int id, int suiteId, String name) => jsonEncode({
    'type': 'testStart',
    'test': {'id': id, 'name': name, 'suiteID': suiteId},
  });

  String error(int testId, String message, [String stack = '']) => jsonEncode({
    'type': 'error',
    'testID': testId,
    'error': message,
    'stackTrace': stack,
    'isFailure': true,
  });

  String done(int testId, String result) => jsonEncode({
    'type': 'testDone',
    'testID': testId,
    'result': result,
    'hidden': false,
    'skipped': false,
  });

  test(
    'lists a failed test with its file, error and stack, and no passing test',
    () {
      final report = failedTests([
        suite(0, 'test/a_test.dart'),
        start(1, 0, 'stays green'),
        done(1, 'success'),
        start(2, 0, 'a group fails an expect'),
        error(
          2,
          'Expected: <2>\n  Actual: <1>\n',
          'test/a_test.dart 8:35  main.<fn>\n',
        ),
        done(2, 'failure'),
      ], root: root);

      expect(
        report,
        contains('### ❌ test/a_test.dart: a group fails an expect'),
      );
      expect(report, contains('Expected: <2>\n  Actual: <1>'));
      expect(report, contains('test/a_test.dart 8:35  main.<fn>'));
      expect(report, isNot(contains('stays green')));
    },
  );

  test('keeps an error raised after a test completed under that test', () {
    final report = failedTests([
      suite(0, 'test/a_test.dart'),
      start(1, 0, 'leaks a timer'),
      done(1, 'success'),
      error(1, 'Bad state: late'),
      error(1, 'This test failed after it had already completed.'),
    ], root: root);

    expect('### ❌'.allMatches(report), hasLength(1));
    expect(report, contains('Bad state: late'));
    expect(
      report,
      contains('This test failed after it had already completed.'),
    );
  });

  test('lists a file that failed to load, with paths relative to the repo', () {
    final report = failedTests([
      suite(0, 'test/broken_test.dart'),
      start(1, 0, 'loading $root/test/broken_test.dart'),
      error(1, 'Failed to load "$root/test/broken_test.dart": no compile'),
      done(1, 'error'),
    ], root: root);

    expect(
      report,
      contains('### ❌ test/broken_test.dart: loading test/broken_test.dart'),
    );
    expect(report, contains('Failed to load "test/broken_test.dart"'));
    expect(report, isNot(contains('$root/')));
  });

  test('says so when flutter test failed without any test failing', () {
    expect(failedTests([], root: root), contains('No test reported an error'));
  });
}
