import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _textField = RegExp(r'\b(TextField|TextFormField|CupertinoTextField)\(');

const _owners = {
  'lib/core/security/zuno_text_field.dart',
  'lib/core/security/secret_text.dart',
};

List<String> rawTextFields(String path, String source) => [
  if (!_owners.contains(path))
    for (final match in _textField.allMatches(source))
      '$path:${'\n'.allMatches(source.substring(0, match.start)).length + 1}',
];

void main() {
  test('a raw text field is reported with its line', () {
    expect(rawTextFields('a.dart', 'x;\nTextField(controller: c);'), [
      'a.dart:2',
    ]);
  });

  test('the app field and the secret field are not reported', () {
    expect(
      rawTextFields('a.dart', 'ZunoTextField(); SecretTextField();'),
      isEmpty,
    );
    expect(
      rawTextFields('lib/core/security/zuno_text_field.dart', 'TextField();'),
      isEmpty,
    );
  });

  test('only ZunoTextField and SecretTextField build a text field', () {
    final raw = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
        ...rawTextFields(file.path, file.readAsStringSync()),
    ];

    expect(
      raw,
      isEmpty,
      reason:
          'ZunoTextField makes every field state its autofill choice and '
          'follow Incognito keyboard; SecretTextField keeps secrets out of '
          'both. Build fields from one of them.',
    );
  });
}
