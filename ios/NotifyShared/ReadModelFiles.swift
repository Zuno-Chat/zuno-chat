import Foundation

enum PreviewLevel: String, Equatable, Sendable {
  case full
  case name
  case none

  init(meta value: String?, stated: Bool) {
    guard stated else {
      self = .full
      return
    }
    self = value.flatMap(PreviewLevel.init(rawValue:)) ?? PreviewLevel.none
  }
}

enum NotifyFile {
  static let meta = "meta"
  static let ledger = "ledger"
  static let ringFlag = "ring.flag"
  static let signedOut = "signed_out"
  static let appLog = "log.app"
  static let nseLog = "log.nse"

  static func room(_ token: String) -> String {
    "rooms/\(token)"
  }
}

struct NotifyMeta: Equatable, Sendable {
  var user: String
  var baseUrl: String
  var serverOffsetMs: Int64?
  var level: PreviewLevel
  var mentionsOnly: Bool
  var tone: Bool
  var ringtone: Bool
  var unread: [String]?
  var heartbeatMs: Int64?
  var mention: NseMentionSpec?
  var askedToJoin: Set<String>

  static func decoded(_ data: Data) -> NotifyMeta? {
    guard let json = NseJson.parse(data, "notify meta parse"), json["v"]?.int64 == 1,
      let user = json["user"]?.string
    else { return nil }
    return NotifyMeta(
      user: user,
      baseUrl: json["base_url"]?.string ?? "",
      serverOffsetMs: json["server_offset_ms"]?.int64,
      level: PreviewLevel(meta: json["level"]?.string, stated: json["level"] != nil),
      mentionsOnly: json["notify"]?.string == "mentions",
      tone: json["tone"]?.bool ?? true,
      ringtone: json["ringtone"]?.bool ?? true,
      unread: json["unread"]?.array?.compactMap(\.string),
      heartbeatMs: json["heartbeat_ms"]?.int64,
      mention: NseMentionSpec(json["mention"]),
      askedToJoin: Set(json["asked"]?.array?.compactMap(\.string) ?? []))
  }
}

struct NotifyRoomFile: Equatable, Sendable {
  var room: String
  var title = ""
  var dm = false
  var partner = ""
  var sessions: [NseSession] = []
  var notifiers: [String] = []

  static func decoded(_ data: Data) -> NotifyRoomFile? {
    guard let json = NseJson.parse(data, "notify room file parse"), json["v"]?.int64 == 1,
      let room = json["room"]?.string
    else { return nil }
    let sessions = (json["sessions"]?.array ?? []).compactMap { item -> NseSession? in
      guard let id = item["session_id"]?.string, let pickle = item["pickle"]?.string,
        let first = item["first_index"]?.int64
      else { return nil }
      return NseSession(
        sessionId: id, sender: item["sender"]?.string, senderKey: item["sender_key"]?.string,
        firstIndex: Int(first), pickle: pickle)
    }
    return NotifyRoomFile(
      room: room, title: json["title"]?.string ?? "", dm: json["dm"]?.bool ?? false,
      partner: json["partner"]?.string ?? "", sessions: sessions,
      notifiers: json["notifiers"]?.array?.compactMap(\.string) ?? [])
  }

  static func decoded(_ data: Data, roomId: String) -> NotifyRoomFile? {
    decoded(data).flatMap { $0.room == roomId ? $0 : nil }
  }

  func session(_ id: String) -> NseSession? {
    sessions.first { $0.sessionId == id }
  }
}
