import Foundation

enum NseJson: Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([NseJson])
  case object([String: NseJson])

  init(_ any: Any) {
    switch any {
    case let value as String:
      self = .string(value)
    case let value as NSNumber:
      self =
        CFGetTypeID(value) == CFBooleanGetTypeID()
        ? .bool(value.boolValue) : .number(value.doubleValue)
    case let value as [Any]:
      self = .array(value.map(NseJson.init))
    case let value as [String: Any]:
      self = .object(value.mapValues(NseJson.init))
    default:
      self = .null
    }
  }

  static func parse(_ data: Data, _ label: String) -> NseJson? {
    CaughtErrors.attempt(label) {
      NseJson(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }
  }

  static func data(_ object: Any, _ label: String) -> Data? {
    CaughtErrors.attempt(label) {
      try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
  }

  subscript(_ key: String) -> NseJson? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  var int64: Int64? {
    guard case .number(let value) = self, value.rounded() == value, abs(value) < 9e15 else {
      return nil
    }
    return Int64(value)
  }

  var array: [NseJson]? {
    if case .array(let value) = self { return value }
    return nil
  }

  var object: [String: NseJson]? {
    if case .object(let value) = self { return value }
    return nil
  }
}

struct NsePush: Equatable, Sendable {
  static let testPrefix = "$zuno_test_"

  let id: String
  let roomId: String?
  let eventId: String?
  let receivedMs: Int64

  init(id: String, roomId: String?, eventId: String?, receivedMs: Int64) {
    self.id = id
    self.roomId = roomId
    self.eventId = eventId
    self.receivedMs = receivedMs
  }

  init(id: String, userInfo: [AnyHashable: Any], receivedMs: Int64) {
    self.init(
      id: id, roomId: userInfo["room_id"] as? String, eventId: userInfo["event_id"] as? String,
      receivedMs: receivedMs)
  }

  var isTest: Bool { eventId?.hasPrefix(Self.testPrefix) ?? false }
}

struct NseMentionSpec: Equatable, Sendable {
  struct Keyword: Equatable, Sendable {
    let pattern: String
    let highlight: Bool
  }

  let mxid: String
  let displayName: String?
  let keywords: [Keyword]
  let rules: [String: Bool]

  init(mxid: String, displayName: String?, keywords: [Keyword], rules: [String: Bool]) {
    self.mxid = mxid
    self.displayName = displayName
    self.keywords = keywords
    self.rules = rules
  }

  init?(_ json: NseJson?) {
    guard let json, let mxid = json["mxid"]?.string else { return nil }
    let keywords = (json["keywords"]?.array ?? []).compactMap { item -> Keyword? in
      guard let pattern = item["pattern"]?.string, !pattern.isEmpty else { return nil }
      return Keyword(pattern: pattern, highlight: item["highlight"]?.bool ?? false)
    }
    let rules = (json["rules"]?.object ?? [:]).compactMapValues(\.bool)
    self.init(
      mxid: mxid, displayName: json["display_name"]?.string, keywords: keywords, rules: rules)
  }
}

struct NseMeta: Equatable, Sendable {
  let user: String
  let baseUrl: String
  let level: PreviewLevel
  let mentionsOnly: Bool
  let tone: Bool
  let ringtone: Bool
  let unread: [String]?
  let heartbeatMs: Int64?
  let mention: NseMentionSpec?

  static func decode(_ data: Data) -> NseMeta? {
    guard let json = NseJson.parse(data, "nse meta parse"), json["v"]?.int64 == 1,
      let user = json["user"]?.string, let baseUrl = json["base_url"]?.string, !baseUrl.isEmpty
    else { return nil }
    return NseMeta(
      user: user,
      baseUrl: baseUrl,
      level: PreviewLevel(meta: json["level"]?.string, stated: json["level"] != nil),
      mentionsOnly: json["notify"]?.string == "mentions",
      tone: json["tone"]?.bool ?? true,
      ringtone: json["ringtone"]?.bool ?? true,
      unread: json["unread"]?.array?.compactMap(\.string),
      heartbeatMs: json["heartbeat_ms"]?.int64,
      mention: NseMentionSpec(json["mention"]))
  }
}

struct NseSession: Equatable, Sendable {
  let sessionId: String
  let sender: String?
  let senderKey: String?
  let firstIndex: Int
  let pickle: String
}

struct NseRoomFile: Equatable, Sendable {
  let room: String
  let title: String?
  let dm: Bool
  let partner: String?
  let sessions: [NseSession]
  let notifiers: [String]

  static func decode(_ data: Data) -> NseRoomFile? {
    guard let json = NseJson.parse(data, "nse room file parse"), json["v"]?.int64 == 1,
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
    return NseRoomFile(
      room: room, title: json["title"]?.string, dm: json["dm"]?.bool ?? false,
      partner: json["partner"]?.string, sessions: sessions,
      notifiers: json["notifiers"]?.array?.compactMap(\.string) ?? [])
  }

  func session(_ id: String) -> NseSession? {
    sessions.first { $0.sessionId == id }
  }
}

struct NseEvent: Equatable, Sendable {
  var eventId: String
  var roomId: String
  var type: String
  var sender: String
  var originServerTs: Int64
  var stateKey: String?
  var redacted: Bool
  var content: NseJson
  var inviteRoomState: [NseJson]

  init(
    eventId: String, roomId: String, type: String, sender: String, originServerTs: Int64,
    stateKey: String? = nil, redacted: Bool = false, content: NseJson = .object([:]),
    inviteRoomState: [NseJson] = []
  ) {
    self.eventId = eventId
    self.roomId = roomId
    self.type = type
    self.sender = sender
    self.originServerTs = originServerTs
    self.stateKey = stateKey
    self.redacted = redacted
    self.content = content
    self.inviteRoomState = inviteRoomState
  }

  init?(_ json: NseJson?) {
    guard let json, let eventId = json["event_id"]?.string, let roomId = json["room_id"]?.string,
      let type = json["type"]?.string, let sender = json["sender"]?.string
    else { return nil }
    self.init(
      eventId: eventId, roomId: roomId, type: type, sender: sender,
      originServerTs: json["origin_server_ts"]?.int64 ?? 0, stateKey: json["state_key"]?.string,
      redacted: json["redacted"]?.bool ?? false, content: json["content"] ?? .object([:]),
      inviteRoomState: json["invite_room_state"]?.array ?? [])
  }
}

struct NseFetched: Equatable, Sendable {
  let event: NseEvent
  let senderName: String?
  let roomName: String?
  let isDm: Bool
  let highlight: Bool
  let serverTs: Int64?
}

struct NseDelivered: Equatable, Sendable {
  let identifier: String
  let dateMs: Int64
  let title: String
  let body: String
  let threadId: String
  let userInfo: [String: String]
  let payloadEventId: String?
  var pushed = true

  var t: String? { userInfo["t"] }
  var e: String? { userInfo["e"] }
  var k: String? { userInfo["k"] }
  var isFloor: Bool { userInfo["f"] == "1" }

  var note: DeliveredNote {
    DeliveredNote(
      identifier: identifier, thread: threadId, roomToken: t,
      seconds: NotificationUserInfo.seconds(userInfo["o"]), appPosted: !pushed)
  }
}
