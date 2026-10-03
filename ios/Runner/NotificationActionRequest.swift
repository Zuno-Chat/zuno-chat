import Foundation

enum NotificationActionKind: String, Equatable, Sendable {
  case reply
  case markRead
}

struct NotificationActionNotice: Equatable, Sendable {
  let notificationId: String
  let title: String
  let thread: String
  let roomId: String?
  let roomToken: String?
}

struct NotificationActionRequest: Equatable, Sendable {
  let id: String
  let kind: NotificationActionKind
  let roomId: String?
  let roomToken: String?
  let eventId: String?
  let eventSeconds: Int?
  let replyText: String?
  let notice: NotificationActionNotice

  var channelValue: [String: Any] {
    var value: [String: Any] = ["id": id, "kind": kind.rawValue]
    if let roomId { value["roomId"] = roomId }
    if let roomToken { value["roomToken"] = roomToken }
    if let eventId { value["eventId"] = eventId }
    if let eventSeconds { value["eventSeconds"] = eventSeconds }
    if let replyText { value["replyText"] = replyText }
    return value
  }
}

struct NotificationActionTarget: Equatable, Sendable {
  let roomId: String?
  let roomToken: String?
  let eventId: String?
  let eventSeconds: Int?

  static func from(userInfo: [AnyHashable: Any]) -> NotificationActionTarget {
    let payload = messagePayload(userInfo["payload"])
    return NotificationActionTarget(
      roomId: text(userInfo["room_id"]) ?? text(payload?["roomId"]),
      roomToken: text(userInfo["t"]) ?? text(payload?["t"]),
      eventId: text(payload?["eventId"]) ?? text(userInfo["event_id"]),
      eventSeconds: seconds(userInfo["o"]) ?? seconds(payload?["o"]))
  }

  private static func messagePayload(_ raw: Any?) -> [String: Any]? {
    guard let json = raw as? String,
      let decoded = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
      decoded["type"] as? String == "message"
    else { return nil }
    return decoded
  }

  private static func text(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return string
  }

  static let latestEventSeconds = 32_503_680_000

  private static func seconds(_ value: Any?) -> Int? {
    let parsed = (value as? String).flatMap { Int($0) } ?? (value as? NSNumber)?.intValue
    guard let parsed, parsed > 0, parsed <= latestEventSeconds else { return nil }
    return parsed
  }
}

enum NotificationActionDecision: Equatable, Sendable {
  case complete
  case replyNotSent(NotificationActionNotice)
  case enqueue(NotificationActionRequest)
}

enum NotificationActionPlanner {
  static func decide(
    action: NotificationAction, notificationId: String, title: String, thread: String,
    userInfo: [AnyHashable: Any], replyText: String?, unlocked: Bool, makeId: () -> String
  ) -> NotificationActionDecision {
    let kind: NotificationActionKind
    switch action {
    case .reply: kind = .reply
    case .markRead: kind = .markRead
    case .open, .dismiss, .other: return .complete
    }
    if kind == .reply,
      (replyText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return .complete
    }
    let target = NotificationActionTarget.from(userInfo: userInfo)
    let notice = NotificationActionNotice(
      notificationId: notificationId, title: title, thread: thread, roomId: target.roomId,
      roomToken: target.roomToken)
    guard target.roomId != nil || target.roomToken != nil, unlocked else {
      return kind == .reply ? .replyNotSent(notice) : .complete
    }
    return .enqueue(
      NotificationActionRequest(
        id: makeId(), kind: kind, roomId: target.roomId, roomToken: target.roomToken,
        eventId: target.eventId, eventSeconds: target.eventSeconds,
        replyText: kind == .reply ? replyText : nil, notice: notice))
  }
}
