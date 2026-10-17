import UserNotifications

enum NotificationCategories {
  static let message = "message"
  static let plainMessage = "message_plain"
  static let replyOnly = "reply"
  static let replyAction = "reply"
  static let markReadAction = "mark_read"

  static var all: Set<UNNotificationCategory> {
    let reply = UNTextInputNotificationAction(
      identifier: replyAction, title: L10n.commonReply, options: [.authenticationRequired],
      textInputButtonTitle: L10n.commonSend, textInputPlaceholder: L10n.commonMessageHint)
    let markRead = UNNotificationAction(
      identifier: markReadAction, title: L10n.commonMarkAsRead, options: [])
    return [
      category(message, actions: [reply, markRead]),
      category(replyOnly, actions: [reply]),
      category(plainMessage, actions: []),
    ]
  }

  private static func category(_ identifier: String, actions: [UNNotificationAction])
    -> UNNotificationCategory
  {
    UNNotificationCategory(
      identifier: identifier, actions: actions, intentIdentifiers: [],
      hiddenPreviewsBodyPlaceholder: L10n.notificationsNewMessage, options: [])
  }

  static func identifier(forKind kind: String, level: String) -> String? {
    guard kind == "msg" else { return nil }
    return level == "full" ? message : plainMessage
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
