import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';
import 'apns_pusher.dart';

enum PushAuthorization {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
  unknown,
}

enum PushSetting { enabled, disabled, notSupported, unknown }

enum PushAlertStyle { none, banner, alert, unknown }

enum PushPreviews { always, whenAuthenticated, never, unknown }

T _named<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((value) => value.name == name).firstOrNull ?? fallback;

@immutable
class PushNotificationSettings {
  const PushNotificationSettings({
    required this.authorization,
    required this.alert,
    required this.sound,
    required this.badge,
    required this.lockScreen,
    required this.notificationCenter,
    required this.carPlay,
    required this.criticalAlert,
    required this.announcement,
    required this.timeSensitive,
    required this.scheduledDelivery,
    required this.directMessages,
    required this.alertStyle,
    required this.previews,
    required this.providesAppSettings,
  });

  factory PushNotificationSettings.fromMap(Map<Object?, Object?> map) {
    PushSetting setting(String key) =>
        _named(PushSetting.values, map[key], PushSetting.unknown);
    return PushNotificationSettings(
      authorization: _named(
        PushAuthorization.values,
        map['authorization'],
        PushAuthorization.unknown,
      ),
      alert: setting('alert'),
      sound: setting('sound'),
      badge: setting('badge'),
      lockScreen: setting('lockScreen'),
      notificationCenter: setting('notificationCenter'),
      carPlay: setting('carPlay'),
      criticalAlert: setting('criticalAlert'),
      announcement: setting('announcement'),
      timeSensitive: setting('timeSensitive'),
      scheduledDelivery: setting('scheduledDelivery'),
      directMessages: setting('directMessages'),
      alertStyle: _named(
        PushAlertStyle.values,
        map['alertStyle'],
        PushAlertStyle.unknown,
      ),
      previews: _named(
        PushPreviews.values,
        map['showPreviews'],
        PushPreviews.unknown,
      ),
      providesAppSettings: map['providesAppSettings'] == true,
    );
  }

  final PushAuthorization authorization;
  final PushSetting alert;
  final PushSetting sound;
  final PushSetting badge;
  final PushSetting lockScreen;
  final PushSetting notificationCenter;
  final PushSetting carPlay;
  final PushSetting criticalAlert;
  final PushSetting announcement;
  final PushSetting timeSensitive;
  final PushSetting scheduledDelivery;
  final PushSetting directMessages;
  final PushAlertStyle alertStyle;
  final PushPreviews previews;
  final bool providesAppSettings;
}

@immutable
class PushDiagnosticsSnapshot {
  const PushDiagnosticsSnapshot({
    required this.settings,
    required this.environment,
    required this.registeredForRemoteNotifications,
  });

  static PushDiagnosticsSnapshot? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final settings = raw['settings'];
    if (settings is! Map) return null;
    return PushDiagnosticsSnapshot(
      settings: PushNotificationSettings.fromMap(settings),
      environment: apnsEnvironmentNamed(raw['environment']),
      registeredForRemoteNotifications:
          raw['registeredForRemoteNotifications'] == true,
    );
  }

  final PushNotificationSettings settings;
  final ApnsEnvironment? environment;
  final bool registeredForRemoteNotifications;
}

class PushDiagnostics {
  PushDiagnostics({
    PlatformCapabilities? capabilities,
    this.channel = const MethodChannel('zuno/push_diag'),
  }) : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;
  final MethodChannel channel;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<PushDiagnosticsSnapshot?> snapshot() async =>
      PushDiagnosticsSnapshot.fromChannel(await rawSnapshot());

  Future<Map<Object?, Object?>?> rawSnapshot() async {
    if (!_capabilities.pushDiagnostics) return null;
    try {
      final raw = await channel.invokeMethod<Object?>('snapshot');
      return raw is Map ? raw : null;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('zuno/push: diagnostics unavailable (${e.code})');
      return null;
    }
  }
}
