import XCTest

@testable import Runner

final class NseStateTests: XCTestCase {
  func testASeenListKeepsTheNewestCopyAndItsLimit() {
    XCTAssertEqual(SeenSets.appending("b", to: ["a", "b", "c"], limit: 3), ["a", "c", "b"])
    XCTAssertEqual(SeenSets.appending("d", to: ["a", "b", "c"], limit: 3), ["b", "c", "d"])
  }

  func testShownTokensComeFromBothWritersAndEachIsClaimedOnce() {
    let files = NseFakeFiles()
    files.put(NotifyFile.shownApp, ["v": 1, "e": ["eApp"]])
    let store = NseStateStore(files: files)

    XCTAssertTrue(store.claim("eNse"))
    XCTAssertFalse(store.claim("eNse"))
    XCTAssertFalse(store.claim("eApp"))
    XCTAssertTrue(store.isShown("eApp"))
    XCTAssertTrue(store.isShown("eNse"))
    XCTAssertFalse(store.isShown("eOther"))
    XCTAssertEqual(files.json(NotifyFile.shownNse)?["e"], .array([.string("eNse")]))
  }

  func testAReleasedClaimCanBeTakenAgain() {
    let store = NseStateStore(files: NseFakeFiles())
    _ = store.claimPending("eNse", process: 1)

    store.release("eNse")

    XCTAssertFalse(store.isShown("eNse"))
    XCTAssertTrue(store.state().pending.isEmpty)
    XCTAssertTrue(store.claim("eNse"))
  }

  func testAPendingClaimLeftByADeadProcessIsReleasedButASettledOneStays() {
    let store = NseStateStore(files: NseFakeFiles())
    XCTAssertTrue(store.claimPending("eDied", process: 1))
    XCTAssertTrue(store.claimPending("ePosted", process: 1))
    store.settle("ePosted")
    XCTAssertTrue(store.claimPending("eLive", process: 2))
    XCTAssertFalse(store.claimPending("eLive", process: 2))

    store.releaseAbandoned(process: 2)

    XCTAssertFalse(store.isShown("eDied"))
    XCTAssertTrue(store.isShown("ePosted"))
    XCTAssertTrue(store.isShown("eLive"))
    XCTAssertEqual(store.state().pending, ["eLive": 2])
  }

  func testARoomFileForAnotherRoomIsIgnored() {
    let files = NseFakeFiles()
    files.put(NotifyFile.room("t1"), ["v": 1, "room": "!other:x", "title": "Other"])

    XCTAssertNil(NseStateStore(files: files).room(token: "t1", roomId: "!abc:zuno.im"))
    XCTAssertNotNil(NseStateStore(files: files).room(token: "t1", roomId: "!other:x"))
  }

  func testMarksKeepTheNewestSixtyFour() {
    let store = NseStateStore(files: NseFakeFiles())
    for ts in 0..<70 { store.appendMark(NseMark(kind: "invite", room: "!r", ts: Int64(ts))) }

    XCTAssertEqual(store.marks().count, 64)
    XCTAssertEqual(store.marks().first?.ts, 6)
  }

  func testTheStateFileRoundTrips() {
    let store = NseStateStore(files: NseFakeFiles())
    store.updateState {
      $0.replay = ["s|1"]
      $0.missed = ["U"]
      $0.pending = ["eP": 1_790_000_000.25]
      $0.version = "2.1 (40)"
    }

    XCTAssertEqual(
      store.state(),
      NseStateFile(
        replay: ["s|1"], missed: ["U"], pending: ["eP": 1_790_000_000.25], version: "2.1 (40)"))
    XCTAssertEqual(NseStateFile.decode(Data("garbage".utf8)), NseStateFile())
  }

  func testTheLedgerIsTheAppsAndAnUnreadableOneIsEmpty() {
    let files = NseFakeFiles()
    let store = NseStateStore(files: files)
    let uuid = CallIdentity.uuid(roomId: "!r", callId: "c")
    var ledger = Ledger()
    ledger.record(uuid: uuid, roomToken: "t1", state: .declined, source: .sync, at: 7)
    _ = files.write(NotifyFile.ledger, ledger.encoded())

    XCTAssertEqual(store.ledger().entry(for: uuid)?.state, .declined)
    _ = files.write(NotifyFile.ledger, Data("garbage".utf8))
    XCTAssertTrue(store.ledger().calls.isEmpty)
    XCTAssertTrue(NseStateStore(files: NseFakeFiles()).ledger().calls.isEmpty)
  }

  func testACleanPushLeavesNoCrash() {
    let defaults = NseFakeDefaults()
    let crumbs = Breadcrumbs(defaults: defaults, processStart: 1)

    XCTAssertFalse(crumbs.begin("p1", nowSeconds: 10))
    crumbs.end("p1")

    XCTAssertTrue(defaults.crumbs(Breadcrumbs.crumbsKey).isEmpty)
    XCTAssertEqual(defaults.integer(Breadcrumbs.crashesKey), 0)
  }

  func testTwoDeadProcessesInARowTurnOnSafeModeForAnHour() {
    let defaults = NseFakeDefaults()
    _ = Breadcrumbs(defaults: defaults, processStart: 1).begin("p1", nowSeconds: 10)
    XCTAssertFalse(Breadcrumbs(defaults: defaults, processStart: 2).begin("p2", nowSeconds: 20))
    XCTAssertEqual(defaults.integer(Breadcrumbs.crashesKey), 1)

    XCTAssertTrue(Breadcrumbs(defaults: defaults, processStart: 3).begin("p3", nowSeconds: 30))
    XCTAssertEqual(defaults.double(Breadcrumbs.safeUntilKey), 3630)
    XCTAssertFalse(
      Breadcrumbs(defaults: defaults, processStart: 3).begin("p4", nowSeconds: 3631))
  }

  func testParallelPushesOfOneLiveProcessAreNotCrashesAndACleanFinishResets() {
    let defaults = NseFakeDefaults()
    let crumbs = Breadcrumbs(defaults: defaults, processStart: 1)
    _ = crumbs.begin("p1", nowSeconds: 10)
    _ = crumbs.begin("p2", nowSeconds: 10)
    XCTAssertEqual(defaults.integer(Breadcrumbs.crashesKey), 0)

    _ = Breadcrumbs(defaults: defaults, processStart: 2).begin("p3", nowSeconds: 20)
    XCTAssertEqual(defaults.integer(Breadcrumbs.crashesKey), 1)
    Breadcrumbs(defaults: defaults, processStart: 2).end("p3")
    XCTAssertEqual(defaults.integer(Breadcrumbs.crashesKey), 0)
  }

  func testCountersBucketEachPushByDayOutcomeTimeAndMemory() {
    let defaults = NseFakeDefaults()
    let counters = NseCounters(defaults: defaults)
    counters.record(
      .utd, nowMs: 1_790_000_000_000, durationMs: 2500, footprintBytes: 9_000_000,
      readModelAgeMs: 120_000)
    counters.record(
      .utd, nowMs: 1_790_000_000_000, durationMs: 400, footprintBytes: nil, readModelAgeMs: nil)

    XCTAssertEqual(defaults.integer("nse.c.20260921.o.utd"), 2)
    XCTAssertEqual(defaults.integer("nse.c.20260921.d.lt3s"), 1)
    XCTAssertEqual(defaults.integer("nse.c.20260921.d.lt1s"), 1)
    XCTAssertEqual(defaults.integer("nse.c.20260921.m.lt12mb"), 1)
    XCTAssertEqual(defaults.integer("nse.c.20260921.a.lt5m"), 1)
  }
}
