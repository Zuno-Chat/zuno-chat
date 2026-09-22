import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _textField = RegExp(r'\b(TextField|TextFormField|CupertinoTextField)\(');

String _callAt(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')' && --depth == 0) return source.substring(open, i + 1);
  }
  return source.substring(open);
}

List<String> textFieldsSilentOnAutofill(String path, String source) => [
  for (final match in _textField.allMatches(source))
    if (!_callAt(source, match.end - 1).contains('autofillHints:'))
      '$path:${'\n'.allMatches(source.substring(0, match.start)).length + 1}',
];

void main() {
  test('a field that names its hints, or opts out, passes', () {
    expect(
      textFieldsSilentOnAutofill('a.dart', '''
        TextField(autofillHints: const [AutofillHints.password]);
        TextField(decoration: InputDecoration(labelText: f(x)), autofillHints: null);
      '''),
      isEmpty,
    );
  });

  test('a field that says nothing is reported with its line', () {
    expect(
      textFieldsSilentOnAutofill('a.dart', 'x;\nTextField(controller: c);'),
      ['a.dart:2'],
    );
  });

  test('every text field in the app states its autofill choice', () {
    final silent = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
        ...textFieldsSilentOnAutofill(file.path, file.readAsStringSync()),
    ];

    expect(
      silent,
      isEmpty,
      reason:
          'Flutter leaves autofill on by default, so an unmarked field opens a '
          'session with the password manager and hands it the text. Set '
          'autofillHints to real hints, or to null to opt out.',
    );
  });
}
