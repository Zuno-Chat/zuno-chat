import UserNotifications
import XCTest

@testable import Runner

final class NotificationResponseRouteTests: XCTestCase {
  private let actions: [NotificationAction] = [.open, .dismiss, .reply, .markRead, .other]

  func testActionIdentifiersMapToTheirActions() {
    XCTAssertEqual(NotificationAction(UNNotificationDefaultActionIdentifier), .open)
    XCTAssertEqual(NotificationAction(UNNotificationDismissActionIdentifier), .dismiss)
    XCTAssertEqual(NotificationAction("reply"), .reply)
    XCTAssertEqual(NotificationAction("mark_read"), .markRead)
    for identifier in ["", "accept", "decline", "Reply", "mark-read"] {
      XCTAssertEqual(NotificationAction(identifier), .other, identifier)
    }
  }

  func testAResponseAPluginHandledNeedsNothingMore() {
    for action in actions {
      XCTAssertEqual(
        route(action, roomId: "!r:x").outcome(handledByPlugin: true), .handled, "\(action)")
    }
  }

  func testATapWithARoomNoPluginTookOpensTheRoom() {
    XCTAssertEqual(
      route(.open, roomId: "!r:x").outcome(handledByPlugin: false), .openRoom("!r:x"))
  }

  func testATapWithoutARoomNoPluginTookOnlyCompletes() {
    XCTAssertEqual(route(.open).outcome(handledByPlugin: false), .complete)
  }

  func testEveryOtherResponseNoPluginTookOnlyCompletes() {
    for action in [NotificationAction.reply, .markRead, .dismiss, .other] {
      XCTAssertEqual(
        route(action, roomId: "!r:x").outcome(handledByPlugin: false), .complete, "\(action)")
    }
  }

  func testAPushedNotificationNoPluginPresentedStaysOutOfTheForeground() {
    XCTAssertEqual(NotificationResponseRoute.presentation(pushed: true), [])
  }

  func testALocalNotificationNoPluginPresentedShowsABannerAndAListEntry() {
    XCTAssertEqual(NotificationResponseRoute.presentation(pushed: false), [.banner, .list])
  }

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

  func testTheRoomComesFromTheRoomIdFirst() {
    let userInfo: [AnyHashable: Any] = [
      "room_id": "!pushed:x", "payload": #"{"type":"message","roomId":"!local:x"}"#,
    ]
    XCTAssertEqual(NotificationResponseRoute.roomId(in: userInfo), "!pushed:x")
  }

  func testTheRoomComesFromAMessagePayload() {
    let userInfo: [AnyHashable: Any] = [
      "payload": #"{"type":"message","roomId":"!r:x","eventId":"$e"}"#
    ]
    XCTAssertEqual(NotificationResponseRoute.roomId(in: userInfo), "!r:x")
  }

  func testANotificationWithoutAReadableRoomHasNoRoom() {
    XCTAssertNil(NotificationResponseRoute.roomId(in: [:]))
    XCTAssertNil(NotificationResponseRoute.roomId(in: ["room_id": 7]))
  }

  func testAnEmptyRoomIdNeverOpensARoom() {
    XCTAssertNil(NotificationResponseRoute.roomId(in: ["room_id": ""]))
    XCTAssertNil(
      NotificationResponseRoute.roomId(in: ["payload": #"{"type":"message","roomId":""}"#]))
    XCTAssertEqual(
      NotificationResponseRoute.roomId(
        in: ["room_id": "", "payload": #"{"type":"message","roomId":"!r:x"}"#]),
      "!r:x")
  }

  func testATapOpensTheRoomBehindTheToken() {
    let known = String(repeating: "a1", count: 16)
    let unknown = String(repeating: "b9", count: 16)
    let resolve: (String) -> String? = { $0 == known ? "!abc:zuno.im" : nil }

    XCTAssertEqual(
      NotificationResponseRoute.roomId(in: ["t": known, "k": "msg"], resolveToken: resolve),
      "!abc:zuno.im")
    XCTAssertEqual(
      NotificationResponseRoute.roomId(in: ["t": unknown], resolveToken: resolve), "t:" + unknown)
    XCTAssertEqual(
      NotificationResponseRoute.roomId(
        in: ["room_id": "!static:zuno.im", "t": known], resolveToken: resolve),
      "!static:zuno.im")
    XCTAssertNil(NotificationResponseRoute.roomId(in: ["t": ""], resolveToken: resolve))
  }

  func testATokenThatIsNotThirtyTwoLowercaseHexCharactersOpensNothing() {
    let resolve: (String) -> String? = { _ in "!abc:zuno.im" }
    let valid = String(repeating: "0f", count: 16)

    XCTAssertEqual(
      NotificationResponseRoute.roomId(in: ["t": valid], resolveToken: resolve), "!abc:zuno.im")
    for token in ["../x", valid.uppercased(), String(valid.dropFirst()), valid + "0"] {
      XCTAssertNil(
        NotificationResponseRoute.roomId(in: ["t": token], resolveToken: resolve), token)
    }
  }

  private func route(_ action: NotificationAction, roomId: String? = nil)
    -> NotificationResponseRoute
  {
    NotificationResponseRoute(action: action, roomId: roomId)
  }
}
