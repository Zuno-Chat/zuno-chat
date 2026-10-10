import XCTest

@testable import Runner

final class NotificationUserInfoTests: XCTestCase {
  func testAnIdIsReadOnlyFromANonEmptyString() {
    XCTAssertEqual(NotificationUserInfo.text("!r:x"), "!r:x")
    let values: [Any?] = ["", 7, NSNull(), nil]
    for value in values {
      XCTAssertNil(NotificationUserInfo.text(value), String(describing: value))
    }
  }

  func testAnEventTimeIsReadFromAStringOrANumber() {
    XCTAssertEqual(NotificationUserInfo.seconds("1790000000"), 1_790_000_000)
    XCTAssertEqual(NotificationUserInfo.seconds(NSNumber(value: 1_790_000_000)), 1_790_000_000)
    let values: [Any?] = ["soon", "", Data(), nil]
    for value in values {
      XCTAssertNil(NotificationUserInfo.seconds(value), String(describing: value))
    }
  }

  func testAMessagePayloadIsReadWhole() throws {
    let fields = try XCTUnwrap(
      NotificationUserInfo.messagePayload(
        in: ["payload": #"{"type":"message","roomId":"!r:x","eventId":"$e"}"#]))

    XCTAssertEqual(fields["roomId"] as? String, "!r:x")
    XCTAssertEqual(fields["eventId"] as? String, "$e")
  }

  func testAPayloadThatIsNotAMessageIsNoMessage() {
    let payloads: [Any] = [
      #"{"type":"newDevice","deviceId":"D","roomId":"!r:x"}"#,
      #"{"roomId":"!r:x"}"#,
      #"["message","!r:x"]"#,
      "not json",
      "",
      42,
    ]
    for payload in payloads {
      XCTAssertNil(NotificationUserInfo.messagePayload(in: ["payload": payload]), "\(payload)")
    }
    XCTAssertNil(NotificationUserInfo.messagePayload(in: [:]))
  }
}
