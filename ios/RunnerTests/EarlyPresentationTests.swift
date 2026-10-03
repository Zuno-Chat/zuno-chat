import UserNotifications
import XCTest

@testable import Runner

final class EarlyPresentationTests: XCTestCase {
  func testCatchUpStaysHiddenAndTheTestNotificationShowsInFront() {
    XCTAssertEqual(
      NotificationResponseRoute.earlyPresentation(identifier: "zuno.catchup.e1", userInfo: [:]),
      [])
    XCTAssertEqual(
      NotificationResponseRoute.earlyPresentation(
        identifier: "x", userInfo: ["k": "sys", "test": "1"]),
      [.banner, .list, .sound])
    XCTAssertEqual(
      NotificationResponseRoute.earlyPresentation(
        identifier: "x", userInfo: ["event_id": "$zuno_test_17"]),
      [.banner, .list, .sound])
    XCTAssertNil(
      NotificationResponseRoute.earlyPresentation(identifier: "x", userInfo: ["k": "msg"]))
  }
}
