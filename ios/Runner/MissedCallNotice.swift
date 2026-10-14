import UserNotifications

enum MissedCallNotice {
  static let identifier = "zuno.missed_before_unlock"

  static func request() -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = L10n.callsMissedCallTitle
    content.body = L10n.callsMissedBeforeUnlock
    return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
  }

  static func post() {
    UNUserNotificationCenter.current().add(request()) { error in
      NotificationFailure.record("missed call notice", error)
    }
  }
}
