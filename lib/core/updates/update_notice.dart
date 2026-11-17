import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_preferences_provider.dart';
import 'find_update.dart';
import 'update_checks.dart';

const updatesDismissedBuildKey = 'updates.dismissed_build';
const _checkEvery = Duration(hours: 6);

final updateChecksEnabledProvider = Provider<bool>((ref) => kReleaseMode);

final updateNoticeProvider =
    NotifierProvider<UpdateNoticeNotifier, AvailableUpdate?>(
      UpdateNoticeNotifier.new,
    );

class UpdateNoticeNotifier extends Notifier<AvailableUpdate?> {
  DateTime? _lastCheck;

  @override
  AvailableUpdate? build() => null;

  Future<void> check() async {
    if (!ref.read(updateChecksEnabledProvider)) return;
    final now = clock.now();
    final last = _lastCheck;
    if (last != null && now.difference(last) < _checkEvery) return;
    _lastCheck = now;
    final AvailableUpdate? update;
    try {
      update = await ref.read(updateFinderProvider)();
    } on Object {
      return;
    }
    if (!ref.mounted || update == null) return;
    final dismissed =
        ref.read(sharedPreferencesProvider).getInt(updatesDismissedBuildKey) ??
        0;
    if (update.build > dismissed) state = update;
  }

  Future<void> dismiss(int shownBuild) async {
    if ((state?.build ?? 0) <= shownBuild) state = null;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(updatesDismissedBuildKey, shownBuild);
  }
}
