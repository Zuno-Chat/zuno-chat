import UserNotifications

enum NotificationCategories {
  static let nativeActions = true
  static let message = "message"
  static let replyOnly = "reply"
  static let replyAction = "reply"
  static let markReadAction = "mark_read"

  static var all: Set<UNNotificationCategory> {
    let reply = UNTextInputNotificationAction(
      identifier: replyAction, title: "Reply", options: [.authenticationRequired],
      textInputButtonTitle: "Send", textInputPlaceholder: "Message")
    let markRead = UNNotificationAction(
      identifier: markReadAction, title: "Mark as read", options: [])
    return [
      UNNotificationCategory(
        identifier: message, actions: [reply, markRead], intentIdentifiers: [], options: []),
      UNNotificationCategory(
        identifier: replyOnly, actions: [reply], intentIdentifiers: [], options: []),
    ]
  }

  static func identifier(forKind kind: String, level: String) -> String? {
    kind == "msg" && level == "full" ? message : nil
  }

  static func shown(_ category: String?) -> String {
    nativeActions ? category ?? "" : ""
  }

  static func register(on center: UNUserNotificationCenter = .current()) {
    center.setNotificationCategories(all)
  }
}

enum NotificationFailure {
  static func record(_ label: String, _ error: (any Error)?) {
    guard let error, (error as? UNError)?.code != .notificationsNotAllowed else { return }
    CaughtErrors.record(label, error)
  }
}
