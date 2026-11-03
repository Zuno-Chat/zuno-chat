import XCTest

@testable import Runner

final class MetricSummaryStoreTests: XCTestCase {
  private var url: URL!

  override func setUp() {
    super.setUp()
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("metrics-\(UUID().uuidString).json")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: url)
    super.tearDown()
  }

  private func summary(_ kind: String, _ end: Int64) -> MetricSummary {
    MetricSummary(kind: kind, endMs: end, counts: ["memory": 1])
  }

  func testRecentSummariesStayForTheDiagnosticsPage() {
    let store = MetricSummaryStore(url: url)
    store.append([summary("exits", 1), summary("crash", 2)])
    XCTAssertEqual(store.recent().map(\.kind), ["exits", "crash"])
    XCTAssertEqual(store.recent().map(\.kind), ["exits", "crash"])
  }

  func testOnlyTheNewestTwentyAreKept() {
    let store = MetricSummaryStore(url: url)
    store.append((0..<25).map { summary("exits", Int64($0)) })
    XCTAssertEqual(store.recent().map(\.endMs), (5..<25).map { Int64($0) })
  }

  func testSummariesSurviveARelaunch() {
    MetricSummaryStore(url: url).append([summary("crash", 3)])
    XCTAssertEqual(MetricSummaryStore(url: url).recent().map(\.kind), ["crash"])
  }

  func testAnUnreadableFileStartsEmpty() throws {
    try Data("not json".utf8).write(to: url)
    let store = MetricSummaryStore(url: url)
    XCTAssertTrue(store.recent().isEmpty)
    store.append([summary("exits", 1)])
    XCTAssertEqual(store.recent().count, 1)
  }

  func testTheChannelValueCarriesKindEndAndCounts() {
    let value = summary("exits", 1_790_000_000_000).channelValue
    XCTAssertEqual(value["kind"] as? String, "exits")
    XCTAssertEqual((value["end_ms"] as? NSNumber)?.int64Value, 1_790_000_000_000)
    XCTAssertEqual(value["counts"] as? [String: Int], ["memory": 1])
  }
}

final class MetricSummariesTests: XCTestCase {
  func testAQuietPeriodIsNotReported() {
    XCTAssertNil(
      MetricSummaries.make(kind: "exits", end: Date(), counts: ["memory": 0, "watchdog": 0]))
  }

  func testOnlyCountsAboveZeroAreKept() {
    let summary = MetricSummaries.make(
      kind: "exits", end: Date(timeIntervalSince1970: 10), counts: ["memory": 2, "watchdog": 0])
    XCTAssertEqual(summary, MetricSummary(kind: "exits", endMs: 10_000, counts: ["memory": 2]))
  }

  func testTerminationReasonsMapOnlyToKnownCauses() {
    XCTAssertEqual(
      MetricSummaries.crashKey(terminationReason: "Namespace RUNNINGBOARD, Code 0xbaadca11"),
      "pushkit_unreported")
    XCTAssertEqual(
      MetricSummaries.crashKey(terminationReason: "Namespace RUNNINGBOARD, Code 0xdead10cc"),
      "locked_file")
    XCTAssertEqual(
      MetricSummaries.crashKey(terminationReason: "Namespace FRONTBOARD, Code 0x8BADF00D"),
      "watchdog")
    XCTAssertNil(MetricSummaries.crashKey(terminationReason: "Namespace SIGNAL, Code 0xb"))
    XCTAssertNil(MetricSummaries.crashKey(terminationReason: nil))
  }

  func testRoutineMemoryReclaimsAreNotReported() {
    let exits = FakeBackgroundExits(cumulativeMemoryPressureExitCount: 3)
    XCTAssertNil(MetricSummaries.exits(exits, end: Date(timeIntervalSince1970: 10)))
  }

  func testGoingOverTheMemoryLimitIsCountedAsOutOfMemory() {
    let exits = FakeBackgroundExits(
      cumulativeMemoryResourceLimitExitCount: 1, cumulativeMemoryPressureExitCount: 3)
    XCTAssertEqual(
      MetricSummaries.exits(exits, end: Date(timeIntervalSince1970: 10)),
      MetricSummary(kind: "exits", endMs: 10_000, counts: ["memory": 1]))
  }

  func testEveryOtherBackgroundExitKeepsItsCount() {
    let exits = FakeBackgroundExits(
      cumulativeSuspendedWithLockedFileExitCount: 1, cumulativeAppWatchdogExitCount: 2,
      cumulativeBackgroundTaskAssertionTimeoutExitCount: 3, cumulativeCPUResourceLimitExitCount: 4,
      cumulativeBadAccessExitCount: 5, cumulativeIllegalInstructionExitCount: 6,
      cumulativeAbnormalExitCount: 7)
    XCTAssertEqual(
      MetricSummaries.exits(exits, end: Date(timeIntervalSince1970: 10))?.counts,
      [
        "locked_file": 1, "watchdog": 2, "task_timeout": 3, "cpu": 4, "bad_access": 11,
        "abnormal": 7,
      ])
  }

  func testEachCountedReasonIsReportedOnItsOwn() {
    XCTAssertEqual(
      MetricSummary(kind: "exits", endMs: 1, counts: ["watchdog": 1, "memory": 2]).reports,
      [
        MetricReport(source: "exits", reason: "memory", summary: "exits memory=2"),
        MetricReport(source: "exits", reason: "watchdog", summary: "exits watchdog=1"),
      ])
  }
}

private struct FakeBackgroundExits: BackgroundExitCounts {
  var cumulativeSuspendedWithLockedFileExitCount = 0
  var cumulativeMemoryResourceLimitExitCount = 0
  var cumulativeMemoryPressureExitCount = 0
  var cumulativeAppWatchdogExitCount = 0
  var cumulativeBackgroundTaskAssertionTimeoutExitCount = 0
  var cumulativeCPUResourceLimitExitCount = 0
  var cumulativeBadAccessExitCount = 0
  var cumulativeIllegalInstructionExitCount = 0
  var cumulativeAbnormalExitCount = 0
}
