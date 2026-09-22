import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/prepared_uia_password.dart';

void main() {
  test('hands the prepared password to the stage that asks', () {
    final prepared = PreparedUiaPassword()..prepare('hunter2');

    expect(prepared.isPrepared, isTrue);
    expect(prepared.take(), 'hunter2');
  });

  test('is consumed on first use, so a rejected one is not re-sent', () {
    final prepared = PreparedUiaPassword()..prepare('wrong');

    expect(prepared.take(), 'wrong');
    expect(prepared.take(), isNull);
    expect(prepared.isPrepared, isFalse);
  });

  test('treats a blank answer as nothing prepared', () {
    expect((PreparedUiaPassword()..prepare('')).take(), isNull);
    expect((PreparedUiaPassword()..prepare(null)).take(), isNull);
  });

  test('nothing is prepared until something prepares it', () {
    final prepared = PreparedUiaPassword();

    expect(prepared.isPrepared, isFalse);
    expect(prepared.take(), isNull);
  });

  test('clear forgets an answer without using it', () {
    final prepared = PreparedUiaPassword()..prepare('hunter2');

    prepared.clear();

    expect(prepared.take(), isNull);
  });
}
