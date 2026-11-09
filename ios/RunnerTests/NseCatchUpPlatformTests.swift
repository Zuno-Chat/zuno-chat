import XCTest

@testable import Runner

final class NseCatchUpPlatformTests: XCTestCase {
  private final class Calls {
    var claimed: [String] = []
    var released: [String] = []
    var settled: [String] = []
    var marked: [NseMark] = []
    var renders: [(String, Bool)] = []
  }

  private func platform(_ calls: Calls) -> NseCatchUpPlatform {
    NseCatchUpPlatform(
      sources: NseCatchUpPlatform.Sources(
        roomToken: { "t" + $0 }, eventToken: { "e" + $0 },
        alreadyShown: { $0 == "e$seen" },
        claim: { token in
          calls.claimed.append(token)
          return token != "e$seen"
        },
        release: { calls.released.append($0) },
        settle: { calls.settled.append($0) },
        mark: { calls.marked.append($0) },
        render: { event, decrypt in
          calls.renders.append((event.eventId, decrypt))
          return .hidden
        }),
      memory: { 7 })
  }

  func testTokensAndSeenEventsComeFromTheExtensionsOwnSources() {
    let subject = platform(Calls())
    XCTAssertEqual(subject.roomToken("!r:hs"), "t!r:hs")
    XCTAssertEqual(subject.eventToken("$e"), "e$e")
    XCTAssertTrue(subject.alreadyShown("e$seen"))
    XCTAssertFalse(subject.alreadyShown("e$new"))
  }

  func testRenderingGoesToTheComposerAndShownEventsToTheSeenSets() throws {
    let calls = Calls()
    let subject = platform(calls)
    let item: [String: Any] = [
      "room_id": "!r:hs", "event_id": "$e", "event": ["origin_server_ts": 1000] as [String: Any],
    ]
    let event = try XCTUnwrap(MissedEvent(json: item))
    XCTAssertEqual(subject.render(event, decrypt: false), .hidden)
    XCTAssertTrue(subject.claim("e$e"))
    XCTAssertFalse(subject.claim("e$seen"))
    subject.release("e$e")
    subject.settle("e$f")
    subject.mark(NseMark(kind: "invite", room: "!r:hs", ts: 1))
    XCTAssertEqual(calls.renders.map { $0.0 }, ["$e"])
    XCTAssertEqual(calls.renders.map { $0.1 }, [false])
    XCTAssertEqual(calls.claimed, ["e$e", "e$seen"])
    XCTAssertEqual(calls.released, ["e$e"])
    XCTAssertEqual(calls.settled, ["e$f"])
    XCTAssertEqual(calls.marked, [NseMark(kind: "invite", room: "!r:hs", ts: 1)])
  }
}
