import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/updates/find_update.dart';
import 'package:zuno/core/updates/update_checks.dart';
import 'package:zuno/core/updates/update_notice.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/preferences_container.dart';

AvailableUpdate _update(int build) =>
    (build: build, link: Uri.parse('https://zuno.chat/download'));

class _Finder {
  _Finder(this.answer);

  AvailableUpdate? Function() answer;
  var calls = 0;

  Future<AvailableUpdate?> find() async {
    calls++;
    return answer();
  }
}

Future<ProviderContainer> _container(
  _Finder finder, {
  bool enabled = true,
  Map<String, Object> stored = const {},
}) => containerWithPreferences(
  stored,
  overrides: [
    updateFinderProvider.overrideWithValue(finder.find),
    updateChecksEnabledProvider.overrideWithValue(enabled),
  ],
);

void main() {
  test('a newer version found becomes the notice', () async {
    final container = await _container(_Finder(() => _update(1007000)));
    await container.read(updateNoticeProvider.notifier).check();
    expect(container.read(updateNoticeProvider), _update(1007000));
  });

  test('outside release builds nothing is checked', () async {
    final finder = _Finder(() => _update(1007000));
    final container = await _container(finder, enabled: false);
    await container.read(updateNoticeProvider.notifier).check();
    expect(finder.calls, 0);
    expect(container.read(updateNoticeProvider), isNull);
  });

  test('a dismissed version stays quiet, a higher one shows', () async {
    final finder = _Finder(() => _update(1007000));
    final container = await _container(
      finder,
      stored: {updatesDismissedBuildKey: 1007000},
    );
    final notice = container.read(updateNoticeProvider.notifier);
    await notice.check();
    expect(container.read(updateNoticeProvider), isNull);

    finder.answer = () => _update(1008000);
    await withClock(
      Clock.fixed(clock.now().add(const Duration(hours: 7))),
      notice.check,
    );
    expect(container.read(updateNoticeProvider), _update(1008000));
  });

  test('dismissing remembers the version and clears the notice', () async {
    final container = await _container(_Finder(() => _update(1007000)));
    final notice = container.read(updateNoticeProvider.notifier);
    await notice.check();
    await notice.dismiss(1007000);
    expect(container.read(updateNoticeProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(updatesDismissedBuildKey), 1007000);
  });

  test('dismissing remembers the version shown, not a newer one found while '
      'the popup was open', () async {
    final finder = _Finder(() => _update(1007000));
    final container = await _container(finder);
    final notice = container.read(updateNoticeProvider.notifier);
    await notice.check();
    finder.answer = () => _update(1008000);
    await withClock(
      Clock.fixed(clock.now().add(const Duration(hours: 7))),
      notice.check,
    );

    await notice.dismiss(1007000);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(updatesDismissedBuildKey), 1007000);
    expect(container.read(updateNoticeProvider), _update(1008000));
  });

  test('a failed check changes nothing and reports nothing', () async {
    final container = await _container(
      _Finder(() => throw StateError('offline')),
    );
    final reports = await caughtDuring(
      () => container.read(updateNoticeProvider.notifier).check(),
    );
    expect(reports, isEmpty);
    expect(container.read(updateNoticeProvider), isNull);
  });

  test('checks at most once every six hours', () async {
    final start = DateTime.utc(2026, 11, 17, 9);
    final finder = _Finder(() => null);
    final container = await _container(finder);
    final notice = container.read(updateNoticeProvider.notifier);
    Future<void> checkAt(Duration after) =>
        withClock(Clock.fixed(start.add(after)), notice.check);

    await checkAt(Duration.zero);
    await checkAt(const Duration(hours: 5));
    expect(finder.calls, 1);
    await checkAt(const Duration(hours: 6));
    expect(finder.calls, 2);
  });
}
