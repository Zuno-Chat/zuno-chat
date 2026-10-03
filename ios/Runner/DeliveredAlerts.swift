import UserNotifications

struct DeliveredAlert: Equatable, Sendable {
  let identifier: String
  let pushed: Bool
  let roomId: String?
  var roomToken: String? = nil
}

extension DeliveredAlert {
  init(_ notification: UNNotification) {
    let userInfo = notification.request.content.userInfo
    self.init(
      identifier: notification.request.identifier,
      pushed: notification.request.trigger is UNPushNotificationTrigger
        || CatchUpComposer.isCatchUp(notification.request.identifier),
      roomId: userInfo["room_id"] as? String, roomToken: userInfo["t"] as? String)
  }
}

protocol DeliveredAlertStore: Sendable {
  func delivered() async -> [DeliveredAlert]
  func remove(_ identifiers: [String])
}

struct SystemDeliveredAlerts: DeliveredAlertStore {
  func delivered() async -> [DeliveredAlert] {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        continuation.resume(returning: notifications.map(DeliveredAlert.init))
      }
    }
  }

  func remove(_ identifiers: [String]) {
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

enum DeliveredAlerts {
  static func identifiers(
    of alerts: [DeliveredAlert], inRooms roomIds: Set<String>, tokens: Set<String> = []
  ) -> [String] {
    alerts.compactMap { alert in
      guard alert.pushed else { return nil }
      if let roomId = alert.roomId, roomIds.contains(roomId) { return alert.identifier }
      if let token = alert.roomToken, tokens.contains(token) { return alert.identifier }
      return nil
    }
  }

  static func remove(
    inRooms roomIds: Set<String>, tokens: Set<String> = [],
    from store: any DeliveredAlertStore = SystemDeliveredAlerts()
  ) async -> Int {
    guard !roomIds.isEmpty else { return 0 }
    let identifiers = identifiers(of: await store.delivered(), inRooms: roomIds, tokens: tokens)
    if !identifiers.isEmpty {
      store.remove(identifiers)
    }
    return identifiers.count
  }
}
