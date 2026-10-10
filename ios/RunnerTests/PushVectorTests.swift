import XCTest

@testable import Runner

final class PushVectorTests: XCTestCase {
  func testCallIdentityGivesEveryFixtureUuid() throws {
    let fixture = try ContractFixture.load("call_uuid_v5.json")
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    XCTAssertEqual(cases.count, 4)
    for entry in cases {
      let roomId = try XCTUnwrap(entry["room_id"])
      let callId = try XCTUnwrap(entry["call_id"])
      XCTAssertEqual(
        CallIdentity.uuid(roomId: roomId, callId: callId).uuidString, entry["uuid"], roomId)
    }
  }
}
