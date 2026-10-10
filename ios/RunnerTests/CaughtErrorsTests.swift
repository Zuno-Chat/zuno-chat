import XCTest

@testable import Runner

private enum ShareFailure: Error {
  case unreadable
}

private struct Wordy: Error, CustomStringConvertible {
  var description: String { String(repeating: "a", count: CaughtErrors.messageLimit + 50) }
}

final class CaughtErrorsTests: XCTestCase {
  private func directory() throws -> URL {
    let base = try makeTemporaryDirectory()
    addTeardownBlock { try? FileManager.default.removeItem(at: base) }
    return base.appendingPathComponent(CaughtErrors.directoryName, isDirectory: true)
  }

  private func files(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
  }

  func testAnErrorIsKeptUntilTakenAndTakingEmptiesTheJournal() throws {
    let caught = CaughtErrors(directory: try directory(), process: "app")

    caught.record("share import", URLError(.timedOut))

    let pending = caught.take()
    XCTAssertEqual(pending.map(\.label), ["share import"])
    XCTAssertEqual(pending.first?.process, "app")
    XCTAssertEqual(pending.first?.domain, NSURLErrorDomain)
    XCTAssertEqual(pending.first?.code, URLError.timedOut.rawValue)
    XCTAssertEqual(caught.take(), [])
    XCTAssertEqual(try files(in: caught.directory), [])
  }

  func testAnAttemptHandsBackItsValueAndRecordsOnlyAFailure() throws {
    let caught = CaughtErrors(directory: try directory(), process: "app")

    let value = caught.attempt("share size") { 7 }
    let failed = caught.attempt("share import") { () throws -> Int in
      throw ShareFailure.unreadable
    }

    XCTAssertEqual(value, 7)
    XCTAssertNil(failed)
    XCTAssertEqual(caught.take().map(\.label), ["share import"])
  }

  func testALabelAlreadyWaitingIsNotRecordedAgain() throws {
    let caught = CaughtErrors(directory: try directory(), process: "app")

    caught.record("share import", ShareFailure.unreadable)
    caught.record("share import", URLError(.badURL))

    XCTAssertEqual(caught.take().map(\.type), [String(reflecting: ShareFailure.self)])
  }

  func testAProcessWithAFullJournalSkipsNewEntries() throws {
    let caught = CaughtErrors(directory: try directory(), process: "app")

    for index in 0...CaughtErrors.limit {
      caught.record("label \(index)", ShareFailure.unreadable)
    }

    let labels = Set(caught.take().map(\.label))
    XCTAssertEqual(labels.count, CaughtErrors.limit)
    XCTAssertFalse(labels.contains("label \(CaughtErrors.limit)"))
  }

  func testEachProcessWritesItsOwnFilesAndTheAppTakesThemAll() throws {
    let shared = try directory()
    let app = CaughtErrors(directory: shared, process: "app")
    let nse = CaughtErrors(directory: shared, process: "nse")
    for index in 0..<CaughtErrors.limit {
      app.record("app \(index)", ShareFailure.unreadable)
    }

    nse.record("nse fetch", ShareFailure.unreadable)
    app.record("nse fetch", ShareFailure.unreadable)

    let pending = CaughtErrors.takeAll(from: [shared])
    XCTAssertEqual(pending.count, CaughtErrors.limit + 1)
    XCTAssertEqual(pending.filter { $0.label == "nse fetch" }.map(\.process), ["nse"])
    XCTAssertEqual(CaughtErrors.takeAll(from: [shared]), [])
  }

  func testAnUnreadableEntryIsDeletedOnceItHasSettled() throws {
    let caught = CaughtErrors(directory: try directory(), process: "app")
    try FileManager.default.createDirectory(at: caught.directory, withIntermediateDirectories: true)
    let settled = caught.directory.appendingPathComponent("nse-settled.json")
    let writing = caught.directory.appendingPathComponent("nse-writing.json")
    try Data("{".utf8).write(to: settled)
    try Data().write(to: writing)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -2 * CaughtErrors.settleSeconds)],
      ofItemAtPath: settled.path)

    XCTAssertEqual(caught.take(), [])

    XCTAssertEqual(try files(in: caught.directory), ["nse-writing.json"])
  }

  func testAnErrorWithUserInfoKeepsItsDescriptionAndUnderlyingCodesOnly() {
    let error = NSError(
      domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
      userInfo: [
        NSLocalizedDescriptionKey: "The file could not be saved.",
        NSFilePathErrorKey: "/private/var/mobile/secret.db",
        NSUnderlyingErrorKey: NSError(
          domain: NSPOSIXErrorDomain, code: Int(ENOSPC),
          userInfo: [NSUnderlyingErrorKey: NSError(domain: "inner", code: 7)]),
      ])

    XCTAssertEqual(
      CaughtErrors.message(error),
      "The file could not be saved.; underlying NSPOSIXErrorDomain 28; underlying inner 7")
  }

  func testASwiftErrorKeepsItsDescriptionCutToTheLimit() {
    XCTAssertEqual(
      CaughtErrors.message(Wordy()), String(repeating: "a", count: CaughtErrors.messageLimit))
    XCTAssertEqual(
      CaughtErrors.message(ShareFailure.unreadable), String(describing: ShareFailure.unreadable))
  }

  func testTheProcessComesFromTheBundleSuffix() {
    XCTAssertEqual(CaughtErrors.process(bundleIdentifier: "im.zuno.chat"), "app")
    XCTAssertEqual(
      CaughtErrors.process(bundleIdentifier: "im.zuno.chat.NotificationService"), "nse")
    XCTAssertEqual(CaughtErrors.process(bundleIdentifier: "im.zuno.chat.ShareExtension"), "share")
  }

  func testWithoutAnAppGroupApplicationSupportHoldsTheJournal() {
    XCTAssertEqual(
      CaughtErrors.directories(bundle: Bundle(for: Self.self)),
      [
        URL.applicationSupportDirectory.appendingPathComponent(
          CaughtErrors.directoryName, isDirectory: true)
      ])
  }
}

@MainActor
final class ErrorsPluginTests: XCTestCase {
  func testTakeHandsOverCrashSummariesAndCaughtErrorsOnce() throws {
    let defaults = UserDefaults(suiteName: "errors-\(UUID().uuidString)")!
    let metrics = MetricsSubscriber(defaults: defaults, log: { _ in })
    metrics.record(["crash exception=1 signal=11"])
    let directory = try makeTemporaryDirectory()
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let caught = CaughtErrors(directory: directory, process: "nse")
    caught.record("nse fetch", ShareFailure.unreadable)
    let plugin = ErrorsPlugin(diagnostics: metrics, caught: { caught.take() })

    let first = immediateReply(from: plugin, method: "take") as? [[String: Any]]
    let second = immediateReply(from: plugin, method: "take") as? [[String: Any]]

    XCTAssertEqual(first?.compactMap { $0["kind"] as? String }, ["crash", "caught"])
    XCTAssertEqual(first?[0]["summary"] as? String, "crash exception=1 signal=11")
    XCTAssertEqual(first?[1]["label"] as? String, "nse fetch")
    XCTAssertEqual(first?[1]["process"] as? String, "nse")
    XCTAssertEqual(second?.count, 0)
  }
}
