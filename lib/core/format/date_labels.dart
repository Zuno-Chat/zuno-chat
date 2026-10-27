import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';

int calendarDaysBetween(DateTime from, DateTime to) {
  DateTime day(DateTime time) {
    final local = time.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  return day(to).difference(day(from)).inDays;
}

String dateLocale(String appLocale, Iterable<Locale> deviceLocales) {
  final language = appLocale.split(RegExp('[_-]')).first;
  for (final device in deviceLocales) {
    if (device.languageCode != language) continue;
    final candidate = Intl.canonicalizedLocale(device.toLanguageTag());
    if (DateFormat.localeExists(candidate)) return candidate;
  }
  return appLocale;
}

class DateLabels {
  DateLabels(this.l10n, {required this.locale, required this.use24Hour});

  factory DateLabels.of(BuildContext context) {
    final l10n = context.l10n;
    return DateLabels(
      l10n,
      locale: dateLocale(
        l10n.localeName,
        View.of(context).platformDispatcher.locales,
      ),
      use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  final AppLocalizations l10n;
  final String locale;
  final bool use24Hour;

  static final _quoted = RegExp("'[^']*'");

  late final DateFormat _clock = _clockFormat();
  late final DateFormat _weekday = DateFormat.E(locale);
  late final DateFormat _monthDay = DateFormat.MMMd(locale);
  late final DateFormat _yearMonthDay = DateFormat.yMMMd(locale);
  late final DateFormat _longMonthDay = DateFormat.MMMMd(locale);
  late final DateFormat _longYearMonthDay = DateFormat.yMMMMd(locale);
  late final DateFormat _yearMonth = DateFormat.yMMMM(locale);

  String clock(DateTime time) => _clock.format(time.toLocal());

  DateFormat _clockFormat() {
    if (use24Hour) return DateFormat.Hm(locale);
    final regional = DateFormat.jm(locale);
    final unquoted = regional.pattern!.replaceAll(_quoted, '');
    return unquoted.contains('a') ? regional : DateFormat('h:mm a', locale);
  }

  String chatList(DateTime at, {required DateTime now}) {
    final daysAgo = calendarDaysBetween(at, now);
    if (daysAgo <= 0) return clock(at);
    if (daysAgo == 1) return l10n.dateYesterday;
    final local = at.toLocal();
    if (daysAgo < 7) return _weekday.format(local);
    final sameYear = local.year == now.toLocal().year;
    return (sameYear ? _monthDay : _yearMonthDay).format(local);
  }

  String day(DateTime time, {required DateTime now}) {
    final daysAgo = calendarDaysBetween(time, now);
    if (daysAgo == 0) return l10n.dateToday;
    if (daysAgo == 1) return l10n.dateYesterday;
    final local = time.toLocal();
    final sameYear = local.year == now.toLocal().year;
    return (sameYear ? _longMonthDay : _longYearMonthDay).format(local);
  }

  String date(DateTime time) => _yearMonthDay.format(time.toLocal());

  String longDate(DateTime time) => _longYearMonthDay.format(time.toLocal());

  String month(DateTime time) => _yearMonth.format(time.toLocal());

  String dateTime(DateTime time) => l10n.dateAtTime(date(time), clock(time));

  String dayAndTime(DateTime time, {required DateTime now}) =>
      l10n.dateAtTime(day(time, now: now), clock(time));

  String age(DateTime at, DateTime now, {bool inSentence = false}) {
    final age = now.difference(at);
    if (age < const Duration(minutes: 1)) {
      return inSentence ? l10n.ageJustNowInSentence : l10n.ageJustNow;
    }
    if (age < const Duration(hours: 1)) return l10n.ageMinutes(age.inMinutes);
    if (age < const Duration(days: 1)) return l10n.ageHours(age.inHours);
    return l10n.ageDays(age.inDays);
  }
}
