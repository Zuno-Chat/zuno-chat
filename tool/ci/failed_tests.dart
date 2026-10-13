import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final report = File(args.single);
  stdout.write(
    failedTests(
      report.existsSync() ? report.readAsLinesSync() : const [],
      root: Directory.current.path,
    ),
  );
}

String failedTests(Iterable<String> report, {required String root}) {
  final paths = <int, String>{};
  final tests = <int, ({String name, int suite})>{};
  final errors = <int, List<String>>{};

  for (final line in report) {
    switch (jsonDecode(line)) {
      case {
        'type': 'suite',
        'suite': {'id': final int id, 'path': final String path},
      }:
        paths[id] = path;
      case {
        'type': 'testStart',
        'test': {
          'id': final int id,
          'name': final String name,
          'suiteID': final int suite,
        },
      }:
        tests[id] = (name: name, suite: suite);
      case {
        'type': 'error',
        'testID': final int id,
        'error': final String error,
        'stackTrace': final String stack,
      }:
        errors.putIfAbsent(id, () => []).add('$error\n$stack'.trimRight());
    }
  }

  if (errors.isEmpty) {
    return 'No test reported an error; flutter test failed outside any '
        'test, see its output above.\n';
  }

  String relative(String text) => text.replaceAll('$root/', '');
  final out = StringBuffer('## Failed tests\n');
  for (final MapEntry(key: id, value: messages) in errors.entries) {
    final test = tests[id]!;
    out
      ..writeln()
      ..writeln('### ❌ ${relative(paths[test.suite]!)}: ${relative(test.name)}')
      ..writeln()
      ..writeln('````')
      ..writeln(relative(messages.join('\n\n')))
      ..writeln('````');
  }
  return out.toString();
}
