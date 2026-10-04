import XCTest

@testable import Runner

final class PushDiagExtrasTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("rooms", isDirectory: true),
      withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func write(_ name: String, _ text: String = "x", modified: Date) throws {
    let url = directory.appendingPathComponent(name)
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
  }

  func testLedgerCallsKeepTheirStateSourceAndTimeButNotTheirIds() throws {
    let calls: [Any] = [
      [
        "uuid": "76204647-3A1F-568F-8647-458C11FDA59D", "t": "2d2de6b6c6565ad95bf365845db19da9",
        "state": "answered", "source": "push", "ts": 1_790_000_000_000,
      ] as [String: Any],
      ["uuid": "x", "state": "missed", "source": "sync"] as [String: Any],
      "junk",
    ]
    let ledger = try XCTUnwrap(PushDiagExtras.ledger(.found(["v": 1, "calls": calls])))
    XCTAssertEqual(ledger.count, 1)
    XCTAssertEqual(ledger.first?["state"] as? String, "answered")
    XCTAssertEqual(ledger.first?["source"] as? String, "push")
    XCTAssertEqual((ledger.first?["ts"] as? NSNumber)?.int64Value, 1_790_000_000_000)
    XCTAssertNil(ledger.first?["uuid"])
    XCTAssertNil(ledger.first?["t"])
  }

  func testNoLedgerFileMeansNoCalls() {
    XCTAssertEqual(PushDiagExtras.ledger(.missing)?.count, 0)
  }

  func testALedgerThatCannotBeReadIsLeftOutInsteadOfReportedEmpty() {
    XCTAssertNil(PushDiagExtras.ledger(.failed))
    XCTAssertNil(PushDiagExtras.ledger(.found(["calls": "x"])))
    for read in [PushDiagExtras.SealedJSON.failed, .found(["calls": "x"])] {
      let extras = PushDiagExtras.collect(directory: nil, readSealed: { _ in read })
      XCTAssertFalse(extras.keys.contains("ledger"))
    }
  }

  func testAtMostSixtyFourCallsAreReported() throws {
    let calls: [Any] = (0..<100).map { index -> [String: Any] in
      ["state": "ended", "source": "push", "ts": index]
    }
    XCTAssertEqual(try XCTUnwrap(PushDiagExtras.ledger(.found(["calls": calls]))).count, 64)
  }

  func testTheReadModelAgeIsTheNewestOfMetaAndRoomFiles() throws {
    try write("meta", modified: Date(timeIntervalSince1970: 1_790_000_000))
    try write("rooms/a", modified: Date(timeIntervalSince1970: 1_790_000_100))
    let extras = PushDiagExtras.collect(directory: directory, readSealed: { _ in .missing })
    let readModel = try XCTUnwrap(extras["read_model"] as? [String: Any])
    XCTAssertEqual((readModel["updated_ms"] as? NSNumber)?.int64Value, 1_790_000_100_000)
  }

  func testTheExtensionsLastRunVersionAndLastTenLinesAreReported() throws {
    let lines = (1...15).map { "line \($0)" }.joined(separator: "\n") + "\n"
    try write("log.nse", lines, modified: Date(timeIntervalSince1970: 1_790_000_200))
    let extras = PushDiagExtras.collect(
      directory: directory,
      readSealed: { $0 == "nse.state" ? .found(["version": "1.2.0 (2)"]) : .missing })
    let nse = try XCTUnwrap(extras["nse"] as? [String: Any])
    XCTAssertEqual((nse["last_run_ms"] as? NSNumber)?.int64Value, 1_790_000_200_000)
    XCTAssertEqual(nse["version"] as? String, "1.2.0 (2)")
    XCTAssertEqual(nse["log"] as? [String], (6...15).map { "line \($0)" })
  }

  func testAnExtensionThatNeverRanReportsOnlyAnEmptyLog() throws {
    let extras = PushDiagExtras.collect(directory: directory, readSealed: { _ in .missing })
    let nse = try XCTUnwrap(extras["nse"] as? [String: Any])
    XCTAssertNil(nse["last_run_ms"])
    XCTAssertNil(nse["version"])
    XCTAssertEqual(nse["log"] as? [String], [])
    XCTAssertEqual((extras["app"] as? [String: Any])?["log"] as? [String], [])
    XCTAssertNil(extras["read_model"])
    XCTAssertEqual((extras["ledger"] as? [[String: Any]])?.count, 0)
  }

  func testTheAppsRingLogTailIsReportedBesideTheExtensionsLog() throws {
    let lines = (1...12).map { "ring \($0)" }.joined(separator: "\n") + "\n"
    try write("log.app", lines, modified: Date(timeIntervalSince1970: 1_790_000_300))
    let extras = PushDiagExtras.collect(directory: directory, readSealed: { _ in .missing })
    let app = try XCTUnwrap(extras["app"] as? [String: Any])
    XCTAssertEqual(app["log"] as? [String], (3...12).map { "ring \($0)" })
  }

  func testWithoutTheSharedDirectoryOnlyTheLedgerIsReported() {
    let extras = PushDiagExtras.collect(
      directory: nil, readSealed: { _ in .found(["calls": [Any]()]) })
    XCTAssertEqual(Set(extras.keys), ["ledger"])
  }

  func testALogThatIsNotTextIsReadWithoutFailing() throws {
    let url = directory.appendingPathComponent("log.nse")
    try Data([0xff, 0xfe, 0x0a, 0x6f, 0x6b]).write(to: url)
    XCTAssertEqual(PushDiagExtras.tail(of: url).last, "ok")
  }

  func testRecentMetricSummariesJoinTheSnapshot() {
    let summary: [String: Any] = ["kind": "exits", "end_ms": Int64(1), "counts": ["memory": 1]]
    let extras = PushDiagExtras.collect(
      directory: nil, readSealed: { _ in .missing }, metrics: [summary])
    XCTAssertEqual((extras["metrics"] as? [[String: Any]])?.count, 1)
    XCTAssertNil(PushDiagExtras.collect(directory: nil, readSealed: { _ in .missing })["metrics"])
  }
}
