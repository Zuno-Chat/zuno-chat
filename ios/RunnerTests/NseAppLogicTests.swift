import XCTest

@testable import Runner

final class NseAppLogicTests: XCTestCase {
  private func floorLine(_ identifier: String, dateMs: Int64) -> NseDelivered {
    NseDelivered(
      identifier: identifier, dateMs: dateMs, title: "", body: "", threadId: "t1",
      userInfo: ["t": "t1", "k": "msg", "f": "1"], payloadEventId: nil)
  }

  func testMarksAreHandedOverOnlyOnce() {
    let marks = [
      NseMark(kind: "invite", room: "!a", ts: 5), NseMark(kind: "test", ts: 9),
    ]

    let first = NseAppLogic.marks(marks, after: 0)
    let again = NseAppLogic.marks(marks, after: first.pointer)

    XCTAssertEqual(first.records.count, 2)
    XCTAssertEqual(first.records.first?["room"] as? String, "!a")
    XCTAssertEqual(first.pointer, 9)
    XCTAssertTrue(again.records.isEmpty)
    XCTAssertEqual(again.pointer, 9)
  }

  func testOutcomesCarryCountersNewMissesAndTheGeneration() {
    let result = NseAppLogic.outcomes(
      counters: ["nse.c.20260921.o.utd": 2],
      utd: [NseUtd(room: "!a", event: "$old", ts: 3), NseUtd(room: "!a", event: "$new", ts: 8)],
      after: 3, generation: "g1")

    XCTAssertEqual(result.records.map { $0["kind"] as? String }, ["counter", "utd", "generation"])
    XCTAssertEqual(result.records[1]["event"] as? String, "$new")
    XCTAssertEqual(result.pointer, 8)
  }

  func testOnlyFinishedDaysOfCountersAreCleared() {
    XCTAssertEqual(
      NseAppLogic.closedDays(
        ["nse.c.20260920.o.shown", "nse.c.20260921.o.shown", "nse.crumbs"], today: "20260921"),
      ["nse.c.20260920.o.shown"])
  }

  func testTheAppBadgeIsTheUnionOfUnreadRoomsAndDeliveredLines() {
    let delivered = [
      NseTestData.delivered("1", t: "t1", k: "msg"), NseTestData.delivered("2", t: "t2", k: "call"),
    ]

    XCTAssertEqual(NseAppLogic.badge(unread: ["t1", "t3"], delivered: delivered), 2)
    XCTAssertEqual(NseAppLogic.badge(unread: [], delivered: []), 0)
  }

  func testSummaryMarksEndTheirRingsOnce() {
    let marks = [
      NseMark(kind: "summary", room: "!a", call: "c1", status: "missed", ts: 4),
      NseMark(kind: "summary", room: "!a", call: "c2", status: "declined", ts: 6),
      NseMark(kind: "invite", room: "!a", ts: 7),
    ]

    let ends = NseAppLogic.ringEnds(marks, after: 4)

    XCTAssertEqual(ends.ends.map(\.callId), ["c2"])
    XCTAssertEqual(ends.ends.first?.declined, true)
    XCTAssertEqual(ends.pointer, 6)
  }

  func testARingRemovesItsFallbackAndTheRoomsRecentFloorsOnly() {
    let now = NseTestData.now
    let fallback = NseDelivered(
      identifier: "ring", dateMs: now - 90_000, title: "", body: "", threadId: "t1",
      userInfo: ["t": "t1", "k": "call", "rg": "r1"], payloadEventId: nil)
    let floor = floorLine("floor", dateMs: now - 5000)
    let oldFloor = floorLine("old", dateMs: now - 60_000)
    let message = NseTestData.delivered("message", t: "t1", dateMs: now - 1000)
    var local = floor
    local.pushed = false

    XCTAssertEqual(
      RingFloorSweeper.identifiers(
        delivered: [fallback, floor, oldFloor, message, local], roomToken: "t1", ringToken: "r1",
        nowMs: now),
      ["ring", "floor"])
  }

  func testACatchUpLineInTheRingingRoomSurvivesTheSweepWhileTheRingsOwnFloorGoes() {
    let now = NseTestData.now
    let floor = floorLine("floor", dateMs: now - 5000)
    let catchUp = NseDelivered(
      identifier: "zuno.catchup.e1", dateMs: now - 3000, title: "", body: "", threadId: "t1",
      userInfo: ["t": "t1", "e": "e1", "o": "100", "k": "msg", "f": "1"], payloadEventId: nil)

    XCTAssertEqual(
      RingFloorSweeper.identifiers(
        delivered: [floor, catchUp], roomToken: "t1", ringToken: "r1", nowMs: now),
      ["floor"])
  }

  func testTheSweepAfterARingRemovesWhatItFound() async {
    let uuid = UUID(uuidString: "76204647-3A1F-568F-8647-458C11FDA59D")!
    let center = NseFakeCenter([
      NseDelivered(
        identifier: "ring", dateMs: NseTestData.now - 60_000, title: "", body: "",
        threadId: "t!abc:zuno.im",
        userInfo: ["t": "t!abc:zuno.im", "k": "call", "rg": "rg\(uuid.uuidString)"],
        payloadEventId: nil)
    ])
    let removed = NseRecorder<[String]>()

    let found = await RingFloorSweeper.sweep(
      roomId: "!abc:zuno.im", callUuid: uuid, hashing: NseFakeHashing(), center: center,
      remove: { removed.add($0) }, nowMs: NseTestData.now)

    XCTAssertEqual(found, ["ring"])
    XCTAssertEqual(removed.values, [["ring"]])
  }

  func testWithoutKeysTheSweepTouchesNothing() async {
    let removed = NseRecorder<[String]>()

    let found = await RingFloorSweeper.sweep(
      roomId: "!abc:zuno.im", callUuid: UUID(), hashing: nil, center: NseFakeCenter(),
      remove: { removed.add($0) }, nowMs: NseTestData.now)

    XCTAssertTrue(found.isEmpty)
    XCTAssertTrue(removed.values.isEmpty)
  }
}
