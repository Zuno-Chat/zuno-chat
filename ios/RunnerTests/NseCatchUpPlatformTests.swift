import XCTest

@testable import Runner

final class NseCatchUpPlatformTests: XCTestCase {
  private final class Calls {
    var recorded: [[String]] = []
    var renders: [(String, Bool)] = []
  }

  private func platform(_ calls: Calls) -> NseCatchUpPlatform {
    NseCatchUpPlatform(
      sources: NseCatchUpPlatform.Sources(
        roomToken: { "t" + $0 }, eventToken: { "e" + $0 },
        alreadyShown: { $0 == "e$seen" },
        recordShown: { calls.recorded.append($0) },
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
    subject.recordShown(["e$e"])
    XCTAssertEqual(calls.renders.map { $0.0 }, ["$e"])
    XCTAssertEqual(calls.renders.map { $0.1 }, [false])
    XCTAssertEqual(calls.recorded, [["e$e"]])
  }

  func testFreeMemoryComesFromTheInjectedReader() {
    XCTAssertEqual(platform(Calls()).availableMemory(), 7)
  }

  func testTheClockIsTheDevicesClock() {
    let before = Date()
    let now = platform(Calls()).now()
    XCTAssertGreaterThanOrEqual(now, before)
  }
}
