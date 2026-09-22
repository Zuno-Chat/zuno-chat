import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/matrix_ids.dart';

void main() {
  test('strips the server part off a user ID', () {
    expect(withoutServer('@alice:example.org'), '@alice');
  });

  test('strips the server part off a room alias', () {
    expect(withoutServer('#general:example.org'), '#general');
  });

  test('a string that is not a valid Matrix ID is returned unchanged', () {
    expect(withoutServer('not a matrix id'), 'not a matrix id');
  });

  test('an empty string is returned unchanged', () {
    expect(withoutServer(''), '');
  });
}
