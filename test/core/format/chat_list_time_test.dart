import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/format/chat_list_time.dart';

void main() {
  final now = DateTime(2026, 9, 20, 15, 30);

  String label(DateTime at, {bool use24Hour = true, DateTime? asOf}) =>
      chatListTimeLabel(at, now: asOf ?? now, use24Hour: use24Hour);

  test('today shows the time, zero-padded on 24-hour', () {
    expect(label(DateTime(2026, 9, 20, 9, 41)), '09:41');
    expect(label(DateTime(2026, 9, 20, 0, 5)), '00:05');
  });

  test('today on 12-hour', () {
    expect(label(DateTime(2026, 9, 20, 9, 41), use24Hour: false), '9:41 AM');
    expect(label(DateTime(2026, 9, 20, 0, 5), use24Hour: false), '12:05 AM');
    expect(label(DateTime(2026, 9, 20, 12, 30), use24Hour: false), '12:30 PM');
    expect(label(DateTime(2026, 9, 20, 15, 7), use24Hour: false), '3:07 PM');
  });

  test('the previous calendar day is Yesterday, even a minute ago', () {
    expect(label(DateTime(2026, 9, 19, 8)), 'Yesterday');
    expect(
      label(DateTime(2026, 9, 19, 23, 59), asOf: DateTime(2026, 9, 20, 0, 1)),
      'Yesterday',
    );
  });

  test('two to six days ago is the weekday', () {
    expect(label(DateTime(2026, 9, 18, 10)), 'Fri');
    expect(label(DateTime(2026, 9, 14, 10)), 'Mon');
  });

  test('a week or more ago in the same year is day and month', () {
    expect(label(DateTime(2026, 9, 13, 10)), '13 Sep');
    expect(label(DateTime(2026, 1, 2, 10)), '2 Jan');
  });

  test('another year adds the year', () {
    expect(label(DateTime(2025, 12, 31, 10)), '31 Dec 2025');
  });

  test('a timestamp in the future is treated as today', () {
    expect(label(DateTime(2026, 9, 20, 15, 35)), '15:35');
    expect(label(DateTime(2026, 9, 21, 0, 10)), '00:10');
  });

  test('a day that is 23 hours long still counts as a day', () {
    expect(
      label(DateTime(2026, 3, 28, 23), asOf: DateTime(2026, 3, 29, 12)),
      'Yesterday',
    );
  });
}
