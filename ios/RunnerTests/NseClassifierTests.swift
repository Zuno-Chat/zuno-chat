import XCTest

@testable import Runner

final class NseClassifierTests: XCTestCase {
  private let now: Int64 = 1_790_000_000_000

  func testEveryVectorLandsInTheAndroidHandlersClass() throws {
    let fixture = try NseFixtures.json("nse_dispatch_v1.json")
    let me = try XCTUnwrap(fixture["me"]?.string)
    for vector in try XCTUnwrap(fixture["cases"]?.array) {
      let actual: String
      switch NseClassifier.classify(
        try NseFixtures.dispatchEvent(vector, now: now), ownUserId: me, nowMs: now)
      {
      case .hidden: actual = "hidden"
      case .ring: actual = "ring"
      case .invitation: actual = "invitation"
      case .verification: actual = "verification"
      case .message: actual = "message"
      }
      XCTAssertEqual(actual, vector["expect"]?["class"]?.string, vector["name"]?.string ?? "")
    }
  }

  func testCallSummariesNameTheCallForTheRingToEnd() {
    let summary = NseEvent(
      eventId: "$s", roomId: "!abc:zuno.im", type: "m.room.message", sender: "@alice:zuno.im",
      originServerTs: now,
      content: .object([
        "msgtype": .string("im.zuno.call_summary"), "call_id": .string("c1"),
        "kind": .string("video"), "status": .string("declined"),
      ]))

    let call = NseClassifier.callSummary(summary)

    XCTAssertEqual(call?.callId, "c1")
    XCTAssertEqual(call?.status, "declined")
    XCTAssertEqual(call?.displayBody, "Video call declined")
  }

  func testAnInviteWithoutACallIdOrKindNeverRings() {
    for content in [
      NseJson.object(["msgtype": .string("im.zuno.call_invite"), "kind": .string("voice")]),
      .object(["msgtype": .string("im.zuno.call_invite"), "call_id": .string("c")]),
    ] {
      let invite = NseEvent(
        eventId: "$i", roomId: "!abc:zuno.im", type: "m.room.message", sender: "@alice:zuno.im",
        originServerTs: now, content: content)
      XCTAssertEqual(
        NseClassifier.classify(invite, ownUserId: "@mwong:zuno.im", nowMs: now), .hidden)
    }
  }

  func testAnEndedCallReadsItsLength() {
    let summary = NseCallSummary(callId: "c", kind: "voice", status: "ended", durationMs: 83_000)

    XCTAssertEqual(summary.displayBody, "Voice call · 1:23")
  }
}
