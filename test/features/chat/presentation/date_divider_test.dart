import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/data/message_kinds.dart';

void main() {
  group('dateDividerLabel', () {
    final now = DateTime(2026, 9, 2, 15);

    test('same calendar day as now is "Today"', () {
      expect(dateDividerLabel(DateTime(2026, 9, 2, 0, 1), now), 'Today');
    });

    test('the day before is "Yesterday"', () {
      expect(dateDividerLabel(DateTime(2026, 9, 1, 23, 59), now), 'Yesterday');
    });

    test('earlier this year: month + day, no year', () {
      expect(dateDividerLabel(DateTime(2026, 1, 15), now), 'January 15');
    });

    test('a previous year: month + day + year', () {
      expect(
        dateDividerLabel(DateTime(2025, 12, 31), now),
        'December 31, 2025',
      );
    });
  });
}
