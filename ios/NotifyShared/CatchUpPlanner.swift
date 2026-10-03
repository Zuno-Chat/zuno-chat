import Foundation

struct PlannedEvent: Sendable {
  let missed: MissedEvent
  let roomToken: String
  let eventToken: String
}

struct PlannedRoom: Sendable {
  let roomToken: String
  let events: [PlannedEvent]

  var newest: PlannedEvent? { events.last }
}

struct CatchUpPlan: Sendable {
  let rooms: [PlannedRoom]
  let moreChats: Int
  let moreRooms: Int
  let unreadRoomTokens: Set<String>
}

enum CatchUpPlanner {
  static let maxRooms = 10

  static func plan(
    _ missed: [MissedEvent], pushedEventId: String?, roomToken: (String) -> String?,
    eventToken: (String) -> String?, alreadyShown: (String) -> Bool,
    maxRooms: Int = CatchUpPlanner.maxRooms
  ) -> CatchUpPlan {
    var seen: Set<String> = []
    var unread: Set<String> = []
    var byRoom: [String: [PlannedEvent]] = [:]
    for event in missed {
      guard event.eventId != pushedEventId, seen.insert(event.eventId).inserted,
        let room = roomToken(event.roomId), let token = eventToken(event.eventId)
      else { continue }
      unread.insert(room)
      guard !alreadyShown(token) else { continue }
      byRoom[room, default: []].append(
        PlannedEvent(missed: event, roomToken: room, eventToken: token))
    }
    let rooms = byRoom.map { room, events in
      PlannedRoom(roomToken: room, events: events.sorted(by: earlier))
    }.sorted(by: busier)
    let limit = max(maxRooms, 0)
    let overflow = rooms.dropFirst(limit)
    let moreChats = overflow.filter { $0.newest?.missed.isDm ?? false }.count
    return CatchUpPlan(
      rooms: Array(rooms.prefix(limit)), moreChats: moreChats,
      moreRooms: overflow.count - moreChats, unreadRoomTokens: unread)
  }

  private static func earlier(_ a: PlannedEvent, _ b: PlannedEvent) -> Bool {
    (a.missed.originServerTs, a.missed.eventId) < (b.missed.originServerTs, b.missed.eventId)
  }

  private static func busier(_ a: PlannedRoom, _ b: PlannedRoom) -> Bool {
    let aNewest = a.newest?.missed.originServerTs ?? 0
    let bNewest = b.newest?.missed.originServerTs ?? 0
    return aNewest != bNewest ? aNewest > bNewest : a.roomToken < b.roomToken
  }
}
