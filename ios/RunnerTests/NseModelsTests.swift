import XCTest

@testable import Runner

final class NseModelsTests: XCTestCase {
  func testAPushReadsSygnalIdsAndSpotsTheTestPrefix() {
    let push = NsePush(
      id: "p", userInfo: ["room_id": "!r:x", "event_id": "$zuno_test_3", "unread_count": 2],
      receivedMs: 9)

    XCTAssertEqual(push.roomId, "!r:x")
    XCTAssertTrue(push.isTest)
    XCTAssertFalse(NsePush(id: "p", userInfo: ["event_id": "$e"], receivedMs: 9).isTest)
    XCTAssertFalse(NsePush(id: "p", userInfo: [:], receivedMs: 9).isTest)
  }

  func testJsonKeepsBooleansApartFromNumbers() throws {
    let json = try XCTUnwrap(
      NseJson.parse(Data(#"{"a":true,"b":1,"c":1.5}"#.utf8), "test json parse"))

    XCTAssertEqual(json["a"], .bool(true))
    XCTAssertEqual(json["b"]?.int64, 1)
    XCTAssertNil(json["c"]?.int64)
    XCTAssertNil(json["a"]?.int64)
  }
}
