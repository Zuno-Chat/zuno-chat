import Foundation
import UserNotifications

protocol CatchUpPlatform: AnyObject {
  func roomToken(_ roomId: String) -> String?
  func eventToken(_ eventId: String) -> String?
  func alreadyShown(_ eventToken: String) -> Bool
  func availableMemory() -> Int
  func render(_ event: MissedEvent, decrypt: Bool) -> CatchUpRender
  func delivered() async -> [DeliveredNote]
  func remove(_ identifiers: [String])
  func post(_ request: UNNotificationRequest) async -> Bool
  func recordShown(_ eventTokens: [String])
  func now() -> Date
}

struct CatchUpOutcome: Equatable, Sendable {
  var readRoomTokens: Set<String> = []
  var unreadRoomTokens: Set<String> = []
  var posted = 0
  var removed: [String] = []
  var hidden = 0
  var floors = 0
  var overflow = 0
}

enum CatchUpBadge {
  static func unread(_ base: Set<String>, after outcome: CatchUpOutcome) -> Set<String> {
    base.subtracting(outcome.readRoomTokens).union(outcome.unreadRoomTokens)
  }
}

enum CatchUp {
  static let decryptFloorBytes = 6 * 1024 * 1024
  static let budget: TimeInterval = 22

  static func run(
    body: [String: Any], level: String, pushedEventId: String?, deadline: Date,
    platform: CatchUpPlatform
  ) async -> CatchUpOutcome {
    let reply = CatchUpReply.parse(body)
    var outcome = CatchUpOutcome()
    let reads = reply.readRooms.compactMap { read in
      platform.roomToken(read.roomId).map { ThreadRead(token: $0, upToMs: read.receiptTs) }
    }
    outcome.readRoomTokens = Set(reads.compactMap(\.token))
    if !reads.isEmpty {
      let delivered = await platform.delivered()
      let identifiers = DeliveredSweep.identifiersToRemove(delivered, reads: reads)
      if !identifiers.isEmpty { platform.remove(identifiers) }
      outcome.removed = identifiers
    }
    guard !reply.missed.isEmpty else { return outcome }
    let plan = CatchUpPlanner.plan(
      reply.missed, pushedEventId: pushedEventId, roomToken: platform.roomToken,
      eventToken: platform.eventToken, alreadyShown: platform.alreadyShown)
    outcome.unreadRoomTokens = plan.unreadRoomTokens
    guard level != "none" else { return outcome }
    outcome.overflow = plan.moreChats + plan.moreRooms
    if platform.now() < deadline,
      let summary = CatchUpComposer.overflowRequest(
        moreChats: plan.moreChats, moreRooms: plan.moreRooms)
    {
      _ = await platform.post(summary)
    }
    var shown: [String] = []
    posting: for room in plan.rooms.reversed() {
      for event in room.events {
        guard platform.now() < deadline else { break posting }
        let decrypt = platform.availableMemory() >= decryptFloorBytes
        guard
          case .shown(let title, let text, let kind, let floor) = platform.render(
            event.missed, decrypt: decrypt)
        else {
          outcome.hidden += 1
          continue
        }
        guard !platform.alreadyShown(event.eventToken) else { continue }
        let request = CatchUpComposer.request(
          for: event, title: title, body: text, kind: kind, floor: floor, level: level)
        if await platform.post(request) {
          shown.append(event.eventToken)
          if floor { outcome.floors += 1 }
        }
      }
    }
    if !shown.isEmpty { platform.recordShown(shown) }
    outcome.posted = shown.count
    return outcome
  }
}
