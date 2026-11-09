import UserNotifications

enum CatchUpRender: Equatable, Sendable {
  case hidden
  case shown(
    title: String, body: String, kind: String, floor: Bool = false, invite: NseInviteClaim? = nil)
}

enum CatchUpComposer {
  static let identifierPrefix = "zuno.catchup."
  static let overflowIdentifier = "zuno.catchup.more"
  static let overflowThread = "zuno.catchup"

  static func request(
    for event: PlannedEvent, title: String, body: String, kind: String, floor: Bool = false,
    claim: String? = nil, level: String
  ) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = event.roomToken
    content.userInfo = NseComposer.userInfo(
      NseTokens(t: event.roomToken, e: event.eventToken, o: Int64(event.missed.seconds)),
      kind: kind, floor: floor, claim: claim)
    content.interruptionLevel = .passive
    content.categoryIdentifier =
      NotificationCategories.identifier(forKind: kind, level: level) ?? ""
    return UNNotificationRequest(
      identifier: identifierPrefix + event.eventToken, content: content, trigger: nil)
  }

  static func overflowRequest(moreChats: Int, moreRooms: Int) -> UNNotificationRequest? {
    guard let body = overflowBody(moreChats: moreChats, moreRooms: moreRooms) else {
      return nil
    }
    let content = UNMutableNotificationContent()
    content.title = "Zuno"
    content.body = body
    content.threadIdentifier = overflowThread
    content.userInfo = ["k": "sys"]
    content.interruptionLevel = .passive
    return UNNotificationRequest(identifier: overflowIdentifier, content: content, trigger: nil)
  }

  static func overflowBody(moreChats: Int, moreRooms: Int) -> String? {
    let chats = max(moreChats, 0)
    let rooms = max(moreRooms, 0)
    switch (chats, rooms) {
    case (0, 0): return nil
    case (_, 0): return L10n.notificationsMoreChats(chats)
    case (0, _): return L10n.notificationsMoreRooms(rooms)
    default: return L10n.notificationsMoreChatsAndRooms(chats + rooms)
    }
  }

  static func isCatchUp(_ identifier: String) -> Bool {
    identifier.hasPrefix(identifierPrefix)
  }
}
