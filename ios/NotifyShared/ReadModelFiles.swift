import Foundation

enum PreviewLevel: String, Equatable, Sendable {
  case full
  case name
  case none
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

struct NotifyMeta: Decodable, Equatable, Sendable {
  var user: String
  var device: String
  var serverOffsetMs: Int64?
  var ringtone: Bool
  var voipCurrent: Bool
  var heartbeatMs: Int64
  var level: PreviewLevel

  private enum CodingKeys: String, CodingKey {
    case v
    case user
    case device
    case serverOffsetMs = "server_offset_ms"
    case ringtone
    case voipCurrent = "voip_current"
    case heartbeatMs = "heartbeat_ms"
    case level
  }

  init(
    user: String, device: String, serverOffsetMs: Int64?, ringtone: Bool, voipCurrent: Bool,
    heartbeatMs: Int64, level: PreviewLevel = .full
  ) {
    self.user = user
    self.device = device
    self.serverOffsetMs = serverOffsetMs
    self.ringtone = ringtone
    self.voipCurrent = voipCurrent
    self.heartbeatMs = heartbeatMs
    self.level = level
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(Int.self, forKey: .v) == 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .v, in: values, debugDescription: "unknown meta version")
    }
    user = try values.decode(String.self, forKey: .user)
    device = try values.decode(String.self, forKey: .device)
    serverOffsetMs = try values.decodeIfPresent(Int64.self, forKey: .serverOffsetMs)
    ringtone = try values.decodeIfPresent(Bool.self, forKey: .ringtone) ?? true
    voipCurrent = try values.decodeIfPresent(Bool.self, forKey: .voipCurrent) ?? false
    heartbeatMs = try values.decodeIfPresent(Int64.self, forKey: .heartbeatMs) ?? 0
    if values.contains(.level) {
      level =
        (try? values.decode(String.self, forKey: .level)).flatMap(PreviewLevel.init(rawValue:))
        ?? PreviewLevel.none
    } else {
      level = .full
    }
  }

  static func decoded(_ data: Data) -> NotifyMeta? {
    try? JSONDecoder().decode(NotifyMeta.self, from: data)
  }
}

struct RoomTitleFile: Decodable, Equatable, Sendable {
  var room: String
  var title: String
  var dm: Bool
  var partner: String

  private enum CodingKeys: String, CodingKey {
    case v
    case room
    case title
    case dm
    case partner
  }

  init(room: String, title: String, dm: Bool, partner: String) {
    self.room = room
    self.title = title
    self.dm = dm
    self.partner = partner
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(Int.self, forKey: .v) == 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .v, in: values, debugDescription: "unknown room file version")
    }
    room = try values.decode(String.self, forKey: .room)
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
    dm = try values.decodeIfPresent(Bool.self, forKey: .dm) ?? false
    partner = try values.decodeIfPresent(String.self, forKey: .partner) ?? ""
  }

  static func decoded(_ data: Data, roomId: String) -> RoomTitleFile? {
    guard let file = try? JSONDecoder().decode(RoomTitleFile.self, from: data),
      file.room == roomId
    else { return nil }
    return file
  }
}
