import XCTest

@testable import Runner

final class NseDispatchVectorTests: XCTestCase {
  private let now: Int64 = 1_790_000_000_000

  private func outcome(of vector: NseJson, me: String) throws -> NseJson {
    let event = try NseFixtures.dispatchEvent(vector, now: now)
    let names = NseNames(
      title: try XCTUnwrap(vector["room"]?["title"]?.string),
      sender: vector["sender_name"]?.string ?? NseComposer.formattedLocalpart(event.sender),
      isDm: vector["room"]?["dm"]?.bool ?? false)
    let fetched = NseFetched(
      event: event, senderName: vector["sender_name"]?.string, roomName: nil, isDm: names.isDm,
      highlight: false, serverTs: now)
    switch NseClassifier.classify(event, ownUserId: me, nowMs: now) {
    case .hidden:
      return .object(["class": .string("hidden")])
    case .ring(let callId, let video):
      return .object(["class": .string("ring"), "call_id": .string(callId), "video": .bool(video)])
    case .invitation(let roomName):
      let inviter = NseComposer.inviter(event: event, fetched: fetched)
      return composed(
        "invitation", NseComposer.invitationLines(inviter: inviter, roomName: roomName))
    case .verification:
      return composed("verification", NseComposer.verificationLines(sender: names.sender))
    case .message(let text, _):
      return composed("message", NseComposer.messageLines(text: text, names: names))
    }
  }

  private func composed(_ kind: String, _ lines: (title: String, body: String)) -> NseJson {
    .object(["class": .string(kind), "title": .string(lines.title), "body": .string(lines.body)])
  }

  func testMatchesTheAndroidHandlerOnEveryVector() throws {
    let fixture = try NseFixtures.json("nse_dispatch_v1.json")
    let me = try XCTUnwrap(fixture["me"]?.string)
    for vector in try XCTUnwrap(fixture["cases"]?.array) {
      XCTAssertEqual(
        try outcome(of: vector, me: me), vector["expect"], vector["name"]?.string ?? "")
    }
  }
}
