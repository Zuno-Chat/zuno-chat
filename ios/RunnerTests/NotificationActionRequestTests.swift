import XCTest

@testable import Runner

final class NotificationActionRequestTests: XCTestCase {
  private let token = "2d2de6b6c6565ad95bf365845db19da9"

  private func decide(
    _ action: NotificationAction, _ userInfo: [AnyHashable: Any], text: String? = nil,
    unlocked: Bool = true
  ) -> NotificationActionDecision {
    NotificationActionPlanner.decide(
      action: action, notificationId: "n1", title: "Maya", thread: "thread-1",
      userInfo: userInfo, replyText: text, unlocked: unlocked, makeId: { "a1" })
  }

  private func notice(roomId: String? = nil, roomToken: String? = nil) -> NotificationActionNotice {
    NotificationActionNotice(
      notificationId: "n1", title: "Maya", thread: "thread-1", roomId: roomId,
      roomToken: roomToken)
  }

  func testAReplyOnAnExtensionNotificationCarriesItsRoomTokenEventTimeAndText() {
    let decision = decide(
      .reply,
      ["t": token, "e": "f79169d67a42d7034d5c3f6a66d7d58a", "o": "1790000000", "k": "msg"],
      text: "on my way")
    XCTAssertEqual(
      decision,
      .enqueue(
        NotificationActionRequest(
          id: "a1", kind: .reply, roomId: nil, roomToken: token, eventId: nil,
          eventSeconds: 1_790_000_000, replyText: "on my way",
          notice: notice(roomToken: token))))
  }

  func testMarkAsReadOnAPostZunoMadeWhileOpenCarriesItsRoomAndEvent() {
    let decision = decide(
      .markRead,
      [
        "NotificationId": 5,
        "payload": #"{"type":"message","roomId":"!r:x","eventId":"$e"}"#,
      ])
    XCTAssertEqual(
      decision,
      .enqueue(
        NotificationActionRequest(
          id: "a1", kind: .markRead, roomId: "!r:x", roomToken: nil, eventId: "$e",
          eventSeconds: nil, replyText: nil, notice: notice(roomId: "!r:x"))))
  }

  func testABlankReplyIsDroppedQuietly() {
    for text in [nil, "", "   ", " \n\t "] {
      XCTAssertEqual(
        decide(.reply, ["t": token], text: text), .complete, "\(String(describing: text))")
    }
  }

  func testAReplyWithNoRoomIsReportedNotSent() {
    XCTAssertEqual(decide(.reply, [:], text: "hi"), .replyNotSent(notice()))
  }

  func testBeforeTheFirstUnlockAReplyIsReportedNotSentAndMarkAsReadOnlyCompletes() {
    XCTAssertEqual(
      decide(.reply, ["t": token], text: "hi", unlocked: false),
      .replyNotSent(notice(roomToken: token)))
    XCTAssertEqual(decide(.markRead, ["t": token], unlocked: false), .complete)
  }

  func testMarkAsReadWithNoRoomOnlyCompletes() {
    XCTAssertEqual(decide(.markRead, ["o": 1_790_000_000]), .complete)
  }

  func testResponsesThatAreNotActionsNeedNothing() {
    for action in [NotificationAction.open, .dismiss, .other] {
      XCTAssertEqual(decide(action, ["t": token], text: "hi"), .complete, "\(action)")
    }
  }

  func testAPayloadThatIsNotAMessageGivesNoRoom() {
    let userInfo: [AnyHashable: Any] = [
      "payload": #"{"type":"newDevice","deviceId":"D","roomId":"!r:x"}"#
    ]
    XCTAssertEqual(decide(.reply, userInfo, text: "hi"), .replyNotSent(notice()))
  }

  func testAnEventTimeThatIsNotAPositiveNumberIsIgnored() {
    let values: [Any] = [0, -3, "0", "soon"]
    for value in values {
      XCTAssertNil(NotificationActionTarget.from(userInfo: ["t": token, "o": value]).eventSeconds)
    }
  }

  func testAnEventTimeBeyondTheYear3000IsIgnoredSoNothingOverflows() {
    let latest = NotificationActionTarget.latestEventSeconds
    XCTAssertEqual(
      NotificationActionTarget.from(userInfo: ["t": token, "o": String(latest)]).eventSeconds,
      latest)
    let values: [Any] = [String(latest + 1), String(Int.max), NSNumber(value: Int.max)]
    for value in values {
      XCTAssertNil(NotificationActionTarget.from(userInfo: ["t": token, "o": value]).eventSeconds)
    }
  }

  func testTheChannelValueLeavesOutWhatIsUnknown() {
    let markRead = NotificationActionRequest(
      id: "a1", kind: .markRead, roomId: nil, roomToken: token, eventId: nil,
      eventSeconds: nil, replyText: nil, notice: notice(roomToken: token))
    XCTAssertEqual(Set(markRead.channelValue.keys), ["id", "kind", "roomToken"])
    XCTAssertEqual(markRead.channelValue["kind"] as? String, "markRead")

    let reply = NotificationActionRequest(
      id: "a2", kind: .reply, roomId: "!r:x", roomToken: token, eventId: "$e",
      eventSeconds: 1_790_000_000, replyText: "hi", notice: notice(roomId: "!r:x"))
    XCTAssertEqual(
      Set(reply.channelValue.keys),
      ["id", "kind", "roomId", "roomToken", "eventId", "eventSeconds", "replyText"])
    XCTAssertEqual(reply.channelValue["eventSeconds"] as? Int, 1_790_000_000)
    XCTAssertEqual(reply.channelValue["kind"] as? String, "reply")
  }
}
