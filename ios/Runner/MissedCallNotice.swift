import UserNotifications

enum MissedCallNotice {
  static let identifier = "zuno.missed_before_unlock"
  static let title = "Missed call"
  static let body = "Unlock this device after a restart to answer calls."

  static func request() -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
  }

  static func post() {
    UNUserNotificationCenter.current().add(request())
  }
}
