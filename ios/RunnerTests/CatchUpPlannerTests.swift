import XCTest

@testable import Runner

final class CatchUpPlannerTests: XCTestCase {
  private func missed(
    _ room: String, _ event: String, at seconds: Int64, dm: Bool = false
  ) throws -> MissedEvent {
    let item: [String: Any] = [
      "room_id": room, "event_id": event, "is_dm": dm,
      "event": ["origin_server_ts": seconds * 1000] as [String: Any],
    ]
    return try XCTUnwrap(MissedEvent(json: item))
  }

  private func plan(
    _ events: [MissedEvent], pushed: String? = "$pushed", shown: Set<String> = [],
    tokens: Bool = true
  ) -> CatchUpPlan {
    CatchUpPlanner.plan(
      events, pushedEventId: pushed,
      roomToken: { tokens ? "t" + $0 : nil }, eventToken: { "e" + $0 },
      alreadyShown: { shown.contains($0) })
  }

  func testEventsAreGroupedPerRoomOldestFirstAndRoomsByNewestActivity() throws {
    let result = plan([
      try missed("!a:hs", "$a2", at: 200), try missed("!b:hs", "$b1", at: 300),
      try missed("!a:hs", "$a1", at: 100),
    ])
    XCTAssertEqual(result.rooms.map(\.roomToken), ["t!b:hs", "t!a:hs"])
    XCTAssertEqual(result.rooms[1].events.map(\.eventToken), ["e$a1", "e$a2"])
    XCTAssertEqual(result.moreChats, 0)
    XCTAssertEqual(result.moreRooms, 0)
  }

  func testThePushedEventAndRepeatsOfAnEventArePlannedOnce() throws {
    let result = plan([
      try missed("!a:hs", "$pushed", at: 100), try missed("!a:hs", "$a1", at: 110),
      try missed("!a:hs", "$a1", at: 110),
    ])
    XCTAssertEqual(result.rooms.flatMap(\.events).map(\.eventToken), ["e$a1"])
  }

  func testEventsAlreadyShownAreSkippedButTheirRoomStaysUnread() throws {
    let result = plan(
      [try missed("!a:hs", "$a1", at: 100), try missed("!b:hs", "$b1", at: 120)],
      shown: ["e$a1"])
    XCTAssertEqual(result.rooms.map(\.roomToken), ["t!b:hs"])
    XCTAssertEqual(result.unreadRoomTokens, ["t!a:hs", "t!b:hs"])
  }

  func testWithoutTokensNothingIsPlanned() throws {
    let result = plan([try missed("!a:hs", "$a1", at: 100)], tokens: false)
    XCTAssertTrue(result.rooms.isEmpty)
    XCTAssertTrue(result.unreadRoomTokens.isEmpty)
  }

  func testAtMostTenRoomsArePlannedAndTheRestCountedAsChatsOrRooms() throws {
    var events = try (0..<10).map { try missed("!r\($0):hs", "$r\($0)", at: 1000 + Int64($0)) }
    events.append(try missed("!chat:hs", "$c1", at: 10, dm: true))
    events.append(try missed("!room:hs", "$m1", at: 20, dm: false))
    let result = plan(events)
    XCTAssertEqual(result.rooms.count, 10)
    XCTAssertFalse(result.rooms.map(\.roomToken).contains("t!chat:hs"))
    XCTAssertEqual(result.moreChats, 1)
    XCTAssertEqual(result.moreRooms, 1)
    XCTAssertEqual(result.unreadRoomTokens.count, 12)
  }

  func testNothingMissedPlansNothing() {
    let result = plan([])
    XCTAssertTrue(result.rooms.isEmpty)
    XCTAssertEqual(result.moreChats + result.moreRooms, 0)
  }
}
