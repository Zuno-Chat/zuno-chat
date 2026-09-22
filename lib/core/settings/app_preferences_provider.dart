import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/crash_reporting.dart';
import '../matrix/matrix_client_provider.dart';
import '../notifications/notification_delivery_mode.dart';
import '../notifications/notification_sound_settings.dart';
import '../notifications/notify_me.dart';
import '../security/screen_security_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart after '
    'SharedPreferences.getInstance() resolves — see matrixClientProvider '
    'for the same pattern.',
  );
});

const _themeModeKey = 'settings.theme_mode';
const _incognitoKeyboardKey = 'settings.incognito_keyboard';
const _sendTypingIndicatorKey = 'settings.send_typing_indicator';
const _linkPreviewsEnabledKey = 'settings.link_previews_enabled';
const _lowDataCallsKey = 'settings.low_data_calls';
const _confirmBeforeCallingKey = 'settings.confirm_before_calling';
const _showHiddenMessagesKey = 'settings.show_hidden_messages';
const _notificationDeliveryModeKey = 'settings.notification_delivery_mode';
const _notificationDeliveryModeChosenKey =
    'settings.notification_delivery_mode_chosen';
const notificationDeliveryModeAutoKey =
    'settings.notification_delivery_mode_auto';
const _reduceMediaSizeKey = 'settings.reduce_media_size';
const _encryptToVerifiedSessionsOnlyKey =
    'settings.encrypt_to_verified_sessions_only';
const _preventScreenshotsKey = 'settings.prevent_screenshots';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(_themeModeKey);
    return ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_themeModeKey, mode.name);
  }
}

final incognitoKeyboardProvider =
    NotifierProvider<IncognitoKeyboardNotifier, bool>(
      IncognitoKeyboardNotifier.new,
    );

class IncognitoKeyboardNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_incognitoKeyboardKey) ??
      true;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_incognitoKeyboardKey, value);
  }
}

final sendTypingIndicatorProvider =
    NotifierProvider<SendTypingIndicatorNotifier, bool>(
      SendTypingIndicatorNotifier.new,
    );

class SendTypingIndicatorNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_sendTypingIndicatorKey) ??
      true;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_sendTypingIndicatorKey, value);
  }
}

const linkPreviewsFeatureAvailable = false;

final linkPreviewsEnabledProvider =
    NotifierProvider<LinkPreviewsEnabledNotifier, bool>(
      LinkPreviewsEnabledNotifier.new,
    );

class LinkPreviewsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_linkPreviewsEnabledKey) ??
      true;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_linkPreviewsEnabledKey, value);
  }
}

final lowDataCallsProvider = NotifierProvider<LowDataCallsNotifier, bool>(
  LowDataCallsNotifier.new,
);

class LowDataCallsNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_lowDataCallsKey) ?? true;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(_lowDataCallsKey, value);
  }
}

final confirmBeforeCallingProvider =
    NotifierProvider<ConfirmBeforeCallingNotifier, bool>(
      ConfirmBeforeCallingNotifier.new,
    );

class ConfirmBeforeCallingNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_confirmBeforeCallingKey) ??
      true;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_confirmBeforeCallingKey, value);
  }
}

final notificationDeliveryModeProvider =
    NotifierProvider<
      NotificationDeliveryModeNotifier,
      NotificationDeliveryMode
    >(NotificationDeliveryModeNotifier.new);

class NotificationDeliveryModeNotifier
    extends Notifier<NotificationDeliveryMode> {
  @override
  NotificationDeliveryMode build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(_notificationDeliveryModeKey);
    return NotificationDeliveryMode.values.asNameMap()[stored] ??
        NotificationDeliveryMode.fcm;
  }

  bool get userChose {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getBool(_notificationDeliveryModeChosenKey) ?? false;
  }

  Future<void> set(NotificationDeliveryMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_notificationDeliveryModeKey, mode.name);
    await prefs.setBool(_notificationDeliveryModeChosenKey, true);
    await prefs.remove(notificationDeliveryModeAutoKey);
  }

  Future<void> autoSelect(NotificationDeliveryMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_notificationDeliveryModeKey, mode.name);
    await prefs.setString(notificationDeliveryModeAutoKey, mode.name);
  }
}

final notifyMeProvider = NotifierProvider<NotifyMeNotifier, NotifyMe>(
  NotifyMeNotifier.new,
);

class NotifyMeNotifier extends Notifier<NotifyMe> {
  @override
  NotifyMe build() =>
      notifyMeFromPreferences(ref.watch(sharedPreferencesProvider));

  Future<void> set(NotifyMe mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(notifyMePreferenceKey, mode.name);
  }
}

final showHiddenMessagesProvider =
    NotifierProvider<ShowHiddenMessagesNotifier, bool>(
      ShowHiddenMessagesNotifier.new,
    );

class ShowHiddenMessagesNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_showHiddenMessagesKey) ??
      false;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_showHiddenMessagesKey, value);
  }
}

final reduceMediaSizeProvider = NotifierProvider<ReduceMediaSizeNotifier, bool>(
  ReduceMediaSizeNotifier.new,
);

class ReduceMediaSizeNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_reduceMediaSizeKey) ?? true;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_reduceMediaSizeKey, value);
  }
}

final encryptToVerifiedSessionsOnlyProvider =
    NotifierProvider<EncryptToVerifiedSessionsOnlyNotifier, bool>(
      EncryptToVerifiedSessionsOnlyNotifier.new,
    );

class EncryptToVerifiedSessionsOnlyNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .watch(sharedPreferencesProvider)
          .getBool(_encryptToVerifiedSessionsOnlyKey) ??
      false;

  Future<void> set(bool value) async {
    state = value;
    ref.read(matrixClientProvider).shareKeysWith = shareKeysWithFor(value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_encryptToVerifiedSessionsOnlyKey, value);
  }
}

bool readEncryptToVerifiedSessionsOnly(SharedPreferences prefs) =>
    prefs.getBool(_encryptToVerifiedSessionsOnlyKey) ?? false;

ShareKeysWith shareKeysWithFor(bool encryptToVerifiedSessionsOnly) =>
    encryptToVerifiedSessionsOnly
    ? ShareKeysWith.directlyVerifiedOnly
    : ShareKeysWith.crossVerifiedIfEnabled;

final preventScreenshotsProvider =
    NotifierProvider<PreventScreenshotsNotifier, bool>(
      PreventScreenshotsNotifier.new,
    );

class PreventScreenshotsNotifier extends Notifier<bool> {
  @override
  bool build() => readPreventScreenshots(ref.watch(sharedPreferencesProvider));

  Future<void> set(bool value) async {
    state = value;
    unawaited(ScreenSecurityService.instance.setPreventScreenshots(value));
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_preventScreenshotsKey, value);
  }
}

bool readPreventScreenshots(SharedPreferences prefs) =>
    prefs.getBool(_preventScreenshotsKey) ?? true;

final crashReportingProvider = NotifierProvider<CrashReportingNotifier, bool>(
  CrashReportingNotifier.new,
);

class CrashReportingNotifier extends Notifier<bool> {
  @override
  bool build() => readCrashReporting(ref.watch(sharedPreferencesProvider));

  Future<void> set(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(setCrashReportingEnabled(prefs, enabled: value));
    await prefs.setBool(crashReportingKey, value);
  }
}

final ringtoneEnabledProvider = NotifierProvider<RingtoneEnabledNotifier, bool>(
  RingtoneEnabledNotifier.new,
);

class RingtoneEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(ringtoneEnabledKey) ??
      NotificationSoundSettings.defaults.ringtone;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(ringtoneEnabledKey, value);
  }
}

final callVibrationEnabledProvider =
    NotifierProvider<CallVibrationEnabledNotifier, bool>(
      CallVibrationEnabledNotifier.new,
    );

class CallVibrationEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(callVibrationEnabledKey) ??
      NotificationSoundSettings.defaults.callVibration;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(callVibrationEnabledKey, value);
  }
}

final messageToneEnabledProvider =
    NotifierProvider<MessageToneEnabledNotifier, bool>(
      MessageToneEnabledNotifier.new,
    );

class MessageToneEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(messageToneEnabledKey) ??
      NotificationSoundSettings.defaults.messageTone;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(messageToneEnabledKey, value);
  }
}

final messageVibrationEnabledProvider =
    NotifierProvider<MessageVibrationEnabledNotifier, bool>(
      MessageVibrationEnabledNotifier.new,
    );

class MessageVibrationEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .watch(sharedPreferencesProvider)
          .getBool(messageVibrationEnabledKey) ??
      NotificationSoundSettings.defaults.messageVibration;

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(messageVibrationEnabledKey, value);
  }
}
