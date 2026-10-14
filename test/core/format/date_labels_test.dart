import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:zuno/core/format/date_labels.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  setUpAll(initializeDateFormatting);

  DateLabels labels(String locale, {bool use24Hour = false}) =>
      DateLabels(englishLocalizations, locale: locale, use24Hour: use24Hour);

  final now = DateTime(2026, 10, 14, 15);

  group('dateLocale', () {
    test('uses the phone region when its language matches the app', () {
      expect(dateLocale('en', const [Locale('en', 'GB')]), 'en_GB');
    });

    test(
      'keeps the app language when the phone language has no translation',
      () {
        expect(dateLocale('en', const [Locale('de', 'DE')]), 'en');
      },
    );

    test('skips a region intl does not know', () {
      expect(dateLocale('en', const [Locale('en', 'ZZ')]), 'en');
    });
  });

  test('one instance formats several dates in a row', () {
    final reused = labels('en', use24Hour: true);
    expect(reused.clock(DateTime(2026, 10, 14, 9, 5)), '09:05');
    expect(reused.clock(DateTime(2026, 10, 14, 21, 30)), '21:30');
    expect(reused.date(DateTime(2026, 3, 2)), 'Mar 2, 2026');
    expect(reused.date(DateTime(2025, 12, 25)), 'Dec 25, 2025');
    expect(reused.longDate(DateTime(2026, 3, 2)), 'March 2, 2026');
    expect(reused.month(DateTime(2026, 3, 2)), 'March 2026');
    expect(reused.chatList(DateTime(2026, 10, 10, 8), now: now), 'Sat');
    expect(reused.chatList(DateTime(2026, 10, 9, 8), now: now), 'Fri');
  });

  group('calendarDaysBetween', () {
    test('counts calendar days, not 24-hour spans', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 10, 13, 23, 59),
          DateTime(2026, 10, 14, 0, 1),
        ),
        1,
      );
      expect(
        calendarDaysBetween(
          DateTime(2026, 10, 14, 0, 1),
          DateTime(2026, 10, 14, 23, 59),
        ),
        0,
      );
    });

    test('crosses a year change', () {
      expect(
        calendarDaysBetween(
          DateTime(2025, 12, 31, 23),
          DateTime(2026, 1, 1, 1),
        ),
        1,
      );
    });

    test('is negative for a later start', () {
      expect(
        calendarDaysBetween(DateTime(2026, 10, 15), DateTime(2026, 10, 14)),
        -1,
      );
    });
  });

  test('day before month in en_GB, month first in en_US', () {
    final at = DateTime(2026, 1, 5, 9);
    expect(labels('en_GB').chatList(at, now: now), '5 Jan');
    expect(labels('en_US').chatList(at, now: now), 'Jan 5');
  });

  test('the 24-hour setting wins over the region', () {
    final at = DateTime(2026, 10, 14, 13, 4);
    expect(labels('en_US', use24Hour: true).clock(at), '13:04');
    expect(labels('en_US').clock(at), DateFormat.jm('en_US').format(at));
  });

  test('chat list: same day shows the clock, midnight rolls to yesterday', () {
    final l = labels('en_US', use24Hour: true);
    expect(l.chatList(DateTime(2026, 10, 14, 0, 1), now: now), '00:01');
    expect(l.chatList(DateTime(2026, 10, 13, 23, 59), now: now), 'Yesterday');
  });

  test('yesterday and this week', () {
    expect(
      labels('en_US').chatList(DateTime(2026, 10, 13, 9), now: now),
      'Yesterday',
    );
    expect(
      labels('en_US').chatList(DateTime(2026, 10, 10, 9), now: now),
      'Sat',
    );
  });

  test('older than a week adds the year only when it differs', () {
    expect(labels('en_US').chatList(DateTime(2026, 9, 1), now: now), 'Sep 1');
    expect(
      labels('en_US').chatList(DateTime(2025, 12, 31), now: now),
      'Dec 31, 2025',
    );
  });

  test('date dividers', () {
    expect(labels('en_US').day(DateTime(2026, 10, 14, 1), now: now), 'Today');
    expect(labels('en_US').day(DateTime(2026, 3, 2), now: now), 'March 2');
    expect(
      labels('en_US').day(DateTime(2025, 3, 2), now: now),
      'March 2, 2025',
    );
  });

  test('a 23-hour day is still the day before', () {
    final l = labels('en_US');
    for (final (day, morningAfter) in [
      (DateTime(2026, 3, 8, 12), DateTime(2026, 3, 9, 0, 30)),
      (DateTime(2026, 3, 29, 12), DateTime(2026, 3, 30, 0, 30)),
    ]) {
      expect(l.day(day, now: morningAfter), 'Yesterday');
      expect(
        l.day(day.subtract(const Duration(days: 1)), now: morningAfter),
        isNot('Yesterday'),
      );
    }
  });

  test('midnight and noon read as 12, not 0', () {
    final l = labels('en_US');
    expect(
      l.clock(DateTime(2026, 1, 1, 0, 0)),
      DateFormat.jm('en_US').format(DateTime(2026, 1, 1, 0, 0)),
    );
    expect(l.clock(DateTime(2026, 1, 1, 0, 0)), startsWith('12:00'));
    expect(l.clock(DateTime(2026, 1, 1, 12, 0)), startsWith('12:00'));
    expect(l.clock(DateTime(2026, 1, 2, 3, 4)), startsWith('3:04'));
  });

  test('a timestamp ahead of now counts as today', () {
    final l = labels('en_US', use24Hour: true);
    expect(l.chatList(DateTime(2026, 10, 14, 18), now: now), '18:00');
    expect(l.chatList(DateTime(2026, 10, 15, 9), now: now), '09:00');
  });

  test('six days back is a weekday, seven days back is a date', () {
    final l = labels('en_US');
    expect(l.chatList(DateTime(2026, 10, 8, 9), now: now), 'Thu');
    expect(l.chatList(DateTime(2026, 10, 7, 9), now: now), 'Oct 7');
  });

  test(
    'the 12-hour setting keeps 12 hours where the region defaults to 24',
    () {
      final at = DateTime(2026, 10, 14, 13, 4);
      expect(
        labels('en_GB').clock(at),
        DateFormat('h:mm a', 'en_GB').format(at),
      );
      expect(labels('en_GB').clock(at), startsWith('1:04'));
      expect(labels('de').clock(at), startsWith('1:04'));
      expect(labels('en_GB', use24Hour: true).clock(at), '13:04');
    },
  );

  test('a region with its own 12-hour pattern keeps it', () {
    final at = DateTime(2026, 10, 14, 13, 4);
    expect(labels('ko').clock(at), DateFormat.jm('ko').format(at));
  });

  test('ages keep their English wording at one and many', () {
    final l = labels('en_US');
    expect(l.age(now, now), 'Just now');
    expect(l.age(now, now, inSentence: true), 'just now');
    expect(l.age(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(l.age(now.subtract(const Duration(hours: 2)), now), '2 h ago');
    expect(l.age(now.subtract(const Duration(days: 1)), now), '1 day ago');
    expect(l.age(now.subtract(const Duration(days: 3)), now), '3 days ago');
  });

  test('date and time joins both parts', () {
    final at = DateTime(2025, 1, 5, 15, 4);
    final l = labels('en_US');
    expect(l.dateTime(at), '${l.date(at)} at ${l.clock(at)}');
  });

  test('a Greek phone gets Greek dates and words', () {
    final greek = DateLabels(
      lookupAppLocalizations(const Locale('el')),
      locale: dateLocale('el', const [Locale('el', 'GR')]),
      use24Hour: true,
    );
    expect(greek.longDate(DateTime(2026, 1, 5)), contains('Ιανουαρίου'));
    expect(greek.day(DateTime(2026, 10, 13, 9), now: now), 'Χθες');
  });

  test('a Portuguese phone gets Portuguese dates and words', () {
    final portuguese = DateLabels(
      lookupAppLocalizations(const Locale('pt', 'PT')),
      locale: dateLocale('pt_PT', const [Locale('pt', 'PT')]),
      use24Hour: true,
    );
    expect(portuguese.longDate(DateTime(2026, 1, 5)), contains('janeiro'));
    expect(portuguese.day(DateTime(2026, 10, 13, 9), now: now), 'Ontem');
  });
}
