@preconcurrency import Flutter
import UIKit
import UserNotifications

struct NotificationSettingsSnapshot: Equatable, Sendable {
  var authorization: UNAuthorizationStatus
  var alert: UNNotificationSetting
  var sound: UNNotificationSetting
  var badge: UNNotificationSetting
  var lockScreen: UNNotificationSetting
  var notificationCenter: UNNotificationSetting
  var carPlay: UNNotificationSetting
  var criticalAlert: UNNotificationSetting
  var announcement: UNNotificationSetting
  var timeSensitive: UNNotificationSetting
  var scheduledDelivery: UNNotificationSetting
  var directMessages: UNNotificationSetting
  var alertStyle: UNAlertStyle
  var showPreviews: UNShowPreviewsSetting
  var providesAppSettings: Bool

  var dictionary: [String: Any] {
    [
      "authorization": Self.name(authorization),
      "alert": Self.name(alert),
      "sound": Self.name(sound),
      "badge": Self.name(badge),
      "lockScreen": Self.name(lockScreen),
      "notificationCenter": Self.name(notificationCenter),
      "carPlay": Self.name(carPlay),
      "criticalAlert": Self.name(criticalAlert),
      "announcement": Self.name(announcement),
      "timeSensitive": Self.name(timeSensitive),
      "scheduledDelivery": Self.name(scheduledDelivery),
      "directMessages": Self.name(directMessages),
      "alertStyle": Self.name(alertStyle),
      "showPreviews": Self.name(showPreviews),
      "providesAppSettings": providesAppSettings,
    ]
  }

  static func name(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    @unknown default: return "unknown"
    }
  }

  static func name(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported: return "notSupported"
    case .disabled: return "disabled"
    case .enabled: return "enabled"
    @unknown default: return "unknown"
    }
  }

  static func name(_ style: UNAlertStyle) -> String {
    switch style {
    case .none: return "none"
    case .banner: return "banner"
    case .alert: return "alert"
    @unknown default: return "unknown"
    }
  }

  static func name(_ previews: UNShowPreviewsSetting) -> String {
    switch previews {
    case .always: return "always"
    case .whenAuthenticated: return "whenAuthenticated"
    case .never: return "never"
    @unknown default: return "unknown"
    }
  }
}

extension NotificationSettingsSnapshot {
  init(_ settings: UNNotificationSettings) {
    self.init(
      authorization: settings.authorizationStatus,
      alert: settings.alertSetting,
      sound: settings.soundSetting,
      badge: settings.badgeSetting,
      lockScreen: settings.lockScreenSetting,
      notificationCenter: settings.notificationCenterSetting,
      carPlay: settings.carPlaySetting,
      criticalAlert: settings.criticalAlertSetting,
      announcement: settings.announcementSetting,
      timeSensitive: settings.timeSensitiveSetting,
      scheduledDelivery: settings.scheduledDeliverySetting,
      directMessages: settings.directMessagesSetting,
      alertStyle: settings.alertStyle,
      showPreviews: settings.showPreviewsSetting,
      providesAppSettings: settings.providesAppNotificationSettings)
  }

  static func current() async -> NotificationSettingsSnapshot {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        continuation.resume(returning: NotificationSettingsSnapshot(settings))
      }
    }
  }
}

enum PushDiagSnapshot {
  static func dictionary(
    settings: NotificationSettingsSnapshot, environment: PushEnvironment, registered: Bool
  ) -> [String: Any] {
    [
      "settings": settings.dictionary,
      "environment": environment.rawValue,
      "registeredForRemoteNotifications": registered,
    ]
  }
}

@MainActor
final class PushDiagPlugin: NSObject, @preconcurrency FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/push_diag", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PushDiagPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "snapshot" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let registered = UIApplication.shared.isRegisteredForRemoteNotifications
    Task {
      let settings = await NotificationSettingsSnapshot.current()
      var snapshot = PushDiagSnapshot.dictionary(
        settings: settings, environment: .current, registered: registered)
      snapshot.merge(
        PushDiagExtras.collect(
          directory: NotifyStore.shared()?.directory, readSealed: PushDiagExtras.readSealed,
          metrics: MetricSummaryStore.standard.recent().map(\.channelValue))
      ) { current, _ in current }
      result(snapshot)
    }
  }
}
