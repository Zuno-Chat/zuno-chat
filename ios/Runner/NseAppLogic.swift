import Foundation

enum NseAppLogic {
  static let generationSeed = "zuno-read-model-generation"

  static func marks(_ marks: [NseMark], after pointer: Int64) -> (
    records: [[String: Any]], pointer: Int64
  ) {
    let fresh = marks.filter { $0.ts > pointer }
    return (fresh.map(\.json), fresh.map(\.ts).max() ?? pointer)
  }

  static func outcomes(
    counters: [String: Int], utd: [NseUtd], after pointer: Int64, generation: String
  ) -> (records: [[String: Any]], pointer: Int64) {
    let fresh = utd.filter { $0.ts > pointer }
    var records: [[String: Any]] = counters.keys.sorted().map {
      ["kind": "counter", "key": $0, "count": counters[$0] ?? 0]
    }
    records += fresh.map { ["kind": "utd", "room": $0.room, "event": $0.event, "ts": $0.ts] }
    records.append(["kind": "generation", "value": generation])
    return (records, fresh.map(\.ts).max() ?? pointer)
  }

  static func closedDays(_ keys: [String], today: String) -> [String] {
    keys.filter { key in
      let day = key.dropFirst(NseCounters.prefix.count).prefix(8)
      return day.count == 8 && day < today
    }
  }

  static func badge(unread: [String], delivered: [NseDelivered]) -> Int {
    NseComposer.badge(unread: unread, delivered: delivered, removed: [], current: nil) ?? 0
  }

  static func ringEnds(_ marks: [NseMark], after pointer: Int64) -> (
    ends: [(roomId: String, callId: String, declined: Bool)], pointer: Int64
  ) {
    let fresh = marks.filter { $0.kind == "summary" && $0.ts > pointer }
    let ends = fresh.compactMap { mark -> (roomId: String, callId: String, declined: Bool)? in
      guard let room = mark.room, let call = mark.call else { return nil }
      return (room, call, mark.status == "declined")
    }
    return (ends, fresh.map(\.ts).max() ?? pointer)
  }
}

enum RingFloorSweeper {
  static let floorWindowMs: Int64 = 20_000

  static func identifiers(
    delivered: [NseDelivered], roomToken: String?, ringToken: String, nowMs: Int64
  ) -> [String] {
    delivered.filter { note in
      guard note.pushed, !CatchUpComposer.isCatchUp(note.identifier) else { return false }
      if note.userInfo["rg"] == ringToken { return true }
      guard let roomToken else { return false }
      return note.t == roomToken && note.isFloor && nowMs - note.dateMs <= floorWindowMs
    }.map(\.identifier)
  }

  static func sweep(
    roomId: String?, callUuid: UUID, hashing: NseHashing?, center: NseDeliveredCenter,
    remove: @Sendable ([String]) -> Void, nowMs: Int64
  ) async -> [String] {
    guard let hashing else { return [] }
    let found = identifiers(
      delivered: await center.delivered(), roomToken: roomId.map(hashing.t),
      ringToken: hashing.rg(callUuid), nowMs: nowMs)
    if !found.isEmpty { remove(found) }
    return found
  }
}
