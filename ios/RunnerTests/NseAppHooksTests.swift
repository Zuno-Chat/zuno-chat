import XCTest

@testable import Runner

final class NseAppHooksTests: XCTestCase {
  func testTheSweepAfterARingRunsOffTheMainActorThroughTheRealCenter() async {
    let ring = RingReported(uuid: UUID(), roomId: "!abc:zuno.im")

    let removed = await NseAppHooks.sweep(after: ring, hashing: NseFakeHashing())

    XCTAssertTrue(removed.isEmpty)
  }

  func testTheSweepRemovesTheFallbackOfTheReportedCall() async {
    let uuid = UUID()
    let ring = RingReported(uuid: uuid, roomId: "!abc:zuno.im")
    let center = NseFakeCenter([
      NseDelivered(
        identifier: "fallback", dateMs: NseTestData.now, title: "", body: "",
        threadId: "t!abc:zuno.im",
        userInfo: ["t": "t!abc:zuno.im", "k": "call", "rg": "rg\(uuid.uuidString)"],
        payloadEventId: nil)
    ])

    let removed = await NseAppHooks.sweep(after: ring, hashing: NseFakeHashing(), center: center)

    XCTAssertEqual(removed, ["fallback"])
  }
}
