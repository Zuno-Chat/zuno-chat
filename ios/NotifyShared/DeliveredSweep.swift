import Foundation
import UserNotifications

struct DeliveredNote: Equatable, Sendable {
  let identifier: String
  let thread: String
  let roomToken: String?
  let seconds: Int?
  var appPosted = false
  var roomId: String? = nil
}

extension DeliveredNote {
  init(_ notification: UNNotification) {
    let content = notification.request.content
    self.init(
      identifier: notification.request.identifier, thread: content.threadIdentifier,
      roomToken: content.userInfo["t"] as? String,
      seconds: NotificationUserInfo.seconds(content.userInfo["o"]),
      appPosted: !notification.isPushed, roomId: content.userInfo["room_id"] as? String)
  }
}

extension UNNotification {
  var isPushed: Bool {
    request.trigger is UNPushNotificationTrigger || CatchUpComposer.isCatchUp(request.identifier)
  }
}

struct ThreadRead: Equatable, Sendable {
  var token: String?
  var roomId: String?
  var upToMs: Int64?
}

enum DeliveredSweep {
  static func identifiersToRemove(_ delivered: [DeliveredNote], reads: [ThreadRead]) -> [String] {
    delivered.filter { note in reads.contains { covers($0, note) } }.map(\.identifier)
  }

  private static func covers(_ read: ThreadRead, _ note: DeliveredNote) -> Bool {
    guard !note.appPosted, isInRoom(note, of: read) else { return false }
    guard let upTo = read.upToMs else { return true }
    guard let seconds = note.seconds else { return false }
    return Int64(seconds) <= upTo / 1000
  }

  private static func isInRoom(_ note: DeliveredNote, of read: ThreadRead) -> Bool {
    if let token = read.token, !token.isEmpty, note.roomToken == token || note.thread == token {
      return true
    }
    guard let roomId = read.roomId, !roomId.isEmpty else { return false }
    return note.roomId == roomId
  }
}
