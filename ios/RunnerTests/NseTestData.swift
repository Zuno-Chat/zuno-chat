import Foundation
import UserNotifications

@testable import Runner

enum NseTestData {
  static let me = "@mwong:zuno.im"
  static let roomId = "!abc:zuno.im"
  static let eventId = "$ev1:zuno.im"
  static let now: Int64 = 1_790_000_000_000
  static let keys = NotifySecrets(
    rmKey: Data(repeating: 1, count: 32), installKey: Data(repeating: 2, count: 32),
    credential: "cred", credentialExpiresTs: now + 86_400_000)

  static func ciphertext(index: UInt8, tag: UInt8) -> String {
    Data([0x03, 0x08, index, 0x12, 0x01, tag]).base64EncodedString()
      .replacingOccurrences(of: "=", with: "")
  }

  static func meta(_ extra: [String: Any] = [:]) -> [String: Any] {
    var meta: [String: Any] = [
      "v": 1, "user": me, "base_url": "https://zuno.im", "level": "full", "notify": "all",
      "tone": true, "ringtone": true, "unread": [String](), "heartbeat_ms": now - 600_000,
    ]
    for (key, value) in extra { meta[key] = value }
    return meta
  }

  static func room(
    title: String = "Design team", dm: Bool = false, sessions: [[String: Any]] = [],
    notifiers: [String] = []
  ) -> [String: Any] {
    [
      "v": 1, "room": roomId, "title": title, "dm": dm, "partner": "", "sessions": sessions,
      "notifiers": notifiers,
    ]
  }

  static func event(
    type: String = "m.room.message", sender: String = "@alice:zuno.im",
    content: [String: Any], ageMs: Int64 = 5000, eventId: String = eventId,
    stateKey: String? = nil
  ) -> [String: Any] {
    var event: [String: Any] = [
      "event_id": eventId, "room_id": roomId, "type": type, "sender": sender,
      "origin_server_ts": now - ageMs, "redacted": false, "content": content,
    ]
    if let stateKey { event["state_key"] = stateKey }
    return event
  }

  static func delivered(
    _ identifier: String, t: String? = "t\(roomId)", e: String? = nil, o: Int64? = nil,
    k: String = "msg", dateMs: Int64 = now - 60_000, title: String = "Design team",
    body: String = "Alice: earlier", threadId: String? = nil, payloadEventId: String? = nil,
    pushed: Bool = true
  ) -> NseDelivered {
    var info: [String: String] = ["k": k]
    if let t { info["t"] = t }
    if let e { info["e"] = e }
    if let o { info["o"] = String(o) }
    return NseDelivered(
      identifier: identifier, dateMs: dateMs, title: title, body: body,
      threadId: threadId ?? t ?? "", userInfo: info, payloadEventId: payloadEventId,
      pushed: pushed)
  }

  static func delivered(_ request: UNNotificationRequest, dateMs: Int64 = now) -> NseDelivered {
    NseDelivered(
      identifier: request.identifier, dateMs: dateMs, title: request.content.title,
      body: request.content.body, threadId: request.content.threadIdentifier,
      userInfo: request.content.userInfo as? [String: String] ?? [:], payloadEventId: nil,
      pushed: false)
  }

  static func push(eventId: String? = eventId) -> NsePush {
    NsePush(id: "push-1", roomId: roomId, eventId: eventId, receivedMs: now)
  }
}
