import XCTest

@testable import Runner

final class TemporaryLeftoversTests: XCTestCase {
  private var temporary: URL!

  override func setUpWithError() throws {
    temporary = try makeTemporaryDirectory()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporary)
  }

  private func write(_ path: String) throws -> URL {
    let file = temporary.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("plain".utf8).write(to: file)
    return file
  }

  private func names(_ urls: [URL]) -> Set<String> {
    Set(urls.map { $0.resolvingSymlinksInPath().path })
  }

  func testEveryFileAnEarlierProcessLeftAtTheTopIsALeftover() throws {
    let voice = try write("a1b2c")
    let saved = try write("report.pdf")
    let recoveryCode = try write("zuno-recovery-code.txt")

    XCTAssertEqual(
      names(TemporaryLeftovers.found(in: temporary)), names([voice, saved, recoveryCode]))
  }

  func testALinkAtTheTopIsALeftoverButItsTargetIsNot() throws {
    let target = try write("kept/clip")
    let link = temporary.appendingPathComponent("clip.mp4")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let found = TemporaryLeftovers.found(in: temporary)

    XCTAssertEqual(found.map(\.lastPathComponent), ["clip.mp4"])
  }

  func testAnUnfinishedExportIsALeftover() throws {
    let export = try write("sensitive-export/\(UUID().uuidString)/zuno-recovery-code.txt")

    XCTAssertEqual(
      names(TemporaryLeftovers.found(in: temporary)),
      names([export.deletingLastPathComponent()]))
  }

  func testOtherFoldersAreLeftAlone() throws {
    _ = try write("com.apple.dyld/cache")

    XCTAssertEqual(TemporaryLeftovers.found(in: temporary), [])
  }

  func testAMissingFolderHasNoLeftovers() {
    XCTAssertEqual(
      TemporaryLeftovers.found(in: temporary.appendingPathComponent("missing")), [])
  }
}
