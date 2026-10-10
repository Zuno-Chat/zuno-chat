import UserNotifications

protocol DeliveredAlertStore: Sendable {
  func delivered() async -> [DeliveredNote]
  func remove(_ identifiers: [String])
}

struct SystemDeliveredAlerts: DeliveredAlertStore {
  func delivered() async -> [DeliveredNote] {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        continuation.resume(returning: notifications.map(DeliveredNote.init))
      }
    }
  }

  func remove(_ identifiers: [String]) {
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

enum DeliveredAlerts {
  static func remove(
    inRooms roomIds: Set<String>, tokens: Set<String> = [],
    from store: any DeliveredAlertStore = SystemDeliveredAlerts()
  ) async -> Int {
    guard !roomIds.isEmpty else { return 0 }
    let reads = roomIds.map { ThreadRead(roomId: $0) } + tokens.map { ThreadRead(token: $0) }
    let identifiers = DeliveredSweep.identifiersToRemove(await store.delivered(), reads: reads)
    if !identifiers.isEmpty {
      store.remove(identifiers)
    }
    return identifiers.count
  }
}
