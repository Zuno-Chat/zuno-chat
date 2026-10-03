import Foundation

struct MissedEvent: @unchecked Sendable {
  let roomId: String
  let eventId: String
  let originServerTs: Int64
  let isDm: Bool
  let senderName: String?
  let roomName: String?
  let highlight: Bool
  let sound: Bool
  let item: [String: Any]

  var seconds: Int { Int(originServerTs / 1000) }

  init?(json value: Any) {
    guard let item = value as? [String: Any],
      let roomId = item["room_id"] as? String, roomId.hasPrefix("!"),
      let eventId = item["event_id"] as? String, eventId.hasPrefix("$"),
      let event = item["event"] as? [String: Any],
      let ts = (event["origin_server_ts"] as? NSNumber)?.int64Value, ts > 0
    else { return nil }
    if let stated = event["room_id"], stated as? String != roomId { return nil }
    if let stated = event["event_id"], stated as? String != eventId { return nil }
    self.roomId = roomId
    self.eventId = eventId
    self.originServerTs = ts
    self.isDm = item["is_dm"] as? Bool ?? false
    self.senderName = item["sender_name"] as? String
    self.roomName = item["room_name"] as? String
    self.highlight = item["highlight"] as? Bool ?? false
    self.sound = item["sound"] as? Bool ?? false
    self.item = item
  }
}

struct ReadRoom: Equatable, Sendable {
  let roomId: String
  let receiptTs: Int64
}

extension ReadRoom {
  init?(json value: Any) {
    guard let item = value as? [String: Any],
      let roomId = item["room_id"] as? String, roomId.hasPrefix("!"),
      let receiptTs = (item["receipt_ts"] as? NSNumber)?.int64Value, receiptTs > 0
    else { return nil }
    self.init(roomId: roomId, receiptTs: receiptTs)
  }
}

struct CatchUpReply: Sendable {
  static let maxMissed = 20
  static let maxReadRooms = 50

  let missed: [MissedEvent]
  let readRooms: [ReadRoom]

  static func parse(_ body: [String: Any]) -> CatchUpReply {
    let missed = (body["missed"] as? [Any] ?? []).prefix(maxMissed)
      .compactMap(MissedEvent.init(json:))
    let readRooms = (body["read_rooms"] as? [Any] ?? []).prefix(maxReadRooms)
      .compactMap(ReadRoom.init(json:))
    return CatchUpReply(missed: missed, readRooms: readRooms)
  }
}
