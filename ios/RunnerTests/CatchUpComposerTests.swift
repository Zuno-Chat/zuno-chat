import UserNotifications
import XCTest

@testable import Runner

final class CatchUpComposerTests: XCTestCase {
  private let roomToken = "2d2de6b6c6565ad95bf365845db19da9"
  private let eventToken = "f79169d67a42d7034d5c3f6a66d7d58a"

  private func planned() throws -> PlannedEvent {
    let item: [String: Any] = [
      "room_id": "!abc:zuno.im", "event_id": "$ev1:zuno.im",
      "event": ["origin_server_ts": 1_790_000_000_999] as [String: Any],
    ]
    let missed = try XCTUnwrap(MissedEvent(json: item))
    return PlannedEvent(missed: missed, roomToken: roomToken, eventToken: eventToken)
  }

  func testACatchUpLineKeepsItsRoomsThreadAndOnlyOpaqueIds() throws {
    let request = CatchUpComposer.request(
      for: try planned(), title: "Design team", body: "Alice: lunch?", kind: "msg", level: "full")
    let content = request.content
    XCTAssertEqual(content.title, "Design team")
    XCTAssertEqual(content.body, "Alice: lunch?")
    XCTAssertEqual(content.threadIdentifier, roomToken)
    XCTAssertEqual(content.userInfo["t"] as? String, roomToken)
    XCTAssertEqual(content.userInfo["e"] as? String, eventToken)
    XCTAssertEqual(content.userInfo["o"] as? String, "1790000000")
    XCTAssertEqual(content.userInfo["k"] as? String, "msg")
    XCTAssertEqual(content.userInfo.count, 4)
    XCTAssertNil(request.trigger)
  }

  func testAFloorSaysSo() throws {
    let content = CatchUpComposer.request(
      for: try planned(), title: "Design team", body: "Alice: New message", kind: "msg",
      floor: true, level: "full"
    ).content
    XCTAssertEqual(content.userInfo["f"] as? String, "1")
    XCTAssertEqual(content.userInfo.count, 5)
  }

  func testItArrivesWithoutSoundOrBanner() throws {
    let content = CatchUpComposer.request(
      for: try planned(), title: "A", body: "B", kind: "msg", level: "full"
    ).content
    XCTAssertEqual(content.interruptionLevel, .passive)
    XCTAssertNil(content.sound)
  }

  func testActionsAttachOnlyToMessagesAtNameAndMessageOnceRoutedNatively() throws {
    let event = try planned()
    func category(_ kind: String, _ level: String) -> String {
      CatchUpComposer.request(for: event, title: "A", body: "B", kind: kind, level: level)
        .content.categoryIdentifier
    }
    XCTAssertEqual(category("msg", "full"), NotificationCategories.shown("message"))
    XCTAssertEqual(category("msg", "name"), "")
  }

  func testEachEventHasItsOwnCatchUpIdentifier() throws {
    let request = CatchUpComposer.request(
      for: try planned(), title: "A", body: "B", kind: "msg", level: "full")
    XCTAssertEqual(request.identifier, "zuno.catchup." + eventToken)
    XCTAssertTrue(CatchUpComposer.isCatchUp(request.identifier))
    XCTAssertTrue(CatchUpComposer.isCatchUp(CatchUpComposer.overflowIdentifier))
    XCTAssertFalse(CatchUpComposer.isCatchUp("8F0C3D2B-36A5-4E3B-9C35-1E2F3A4B5C6D"))
    XCTAssertFalse(CatchUpComposer.isCatchUp("zuno.reply_not_sent.!r:x"))
  }

  func testTheSummaryCountsTheChatsAndRoomsLeftOver() {
    XCTAssertEqual(
      CatchUpComposer.overflowBody(moreChats: 1, moreRooms: 0), "New messages in 1 more chat")
    XCTAssertEqual(
      CatchUpComposer.overflowBody(moreChats: 3, moreRooms: 0), "New messages in 3 more chats")
    XCTAssertEqual(
      CatchUpComposer.overflowBody(moreChats: 0, moreRooms: 1), "New messages in 1 more room")
    XCTAssertEqual(
      CatchUpComposer.overflowBody(moreChats: 0, moreRooms: 2), "New messages in 2 more rooms")
    XCTAssertEqual(
      CatchUpComposer.overflowBody(moreChats: 2, moreRooms: 1),
      "New messages in 3 more chats and rooms")
  }

  func testNothingLeftOverMeansNoSummary() {
    XCTAssertNil(CatchUpComposer.overflowBody(moreChats: 0, moreRooms: 0))
    XCTAssertNil(CatchUpComposer.overflowBody(moreChats: -1, moreRooms: 0))
    XCTAssertNil(CatchUpComposer.overflowRequest(moreChats: 0, moreRooms: 0))
  }

  func testTheSummaryQuietlyReplacesTheLastOne() throws {
    let request = try XCTUnwrap(CatchUpComposer.overflowRequest(moreChats: 1, moreRooms: 1))
    XCTAssertEqual(request.identifier, "zuno.catchup.more")
    XCTAssertEqual(request.content.title, "Zuno")
    XCTAssertEqual(request.content.threadIdentifier, "zuno.catchup")
    XCTAssertEqual(request.content.userInfo["k"] as? String, "sys")
    XCTAssertEqual(request.content.interruptionLevel, .passive)
    XCTAssertNil(request.content.sound)
    XCTAssertEqual(request.content.categoryIdentifier, "")
  }
}
