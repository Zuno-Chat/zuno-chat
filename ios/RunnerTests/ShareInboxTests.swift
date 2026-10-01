import UniformTypeIdentifiers
import XCTest

@testable import Runner

final class ShareFileNameTests: XCTestCase {
  func testSlashesBecomeUnderscoresAsOnAndroid() {
    XCTAssertEqual(ShareFileName.safe("a/b\\c.txt"), "a_b_c.txt")
    XCTAssertEqual(ShareFileName.safe(".env"), ".env")
  }

  func testEmptyAndDotNamesFallBackToShared() {
    XCTAssertEqual(ShareFileName.safe(""), "shared")
    XCTAssertEqual(ShareFileName.safe("."), "shared")
    XCTAssertEqual(ShareFileName.safe(".."), "shared")
  }

  func testANameWithoutAnExtensionGetsOneFromItsType() {
    XCTAssertEqual(
      ShareFileName.named("IMG_0001", typeIdentifier: UTType.png.identifier), "IMG_0001.png")
    XCTAssertEqual(
      ShareFileName.named("  notes ", typeIdentifier: UTType.pdf.identifier), "notes.pdf")
    XCTAssertEqual(ShareFileName.named(nil, typeIdentifier: UTType.png.identifier), "shared.png")
  }

  func testAnExistingExtensionIsKept() {
    XCTAssertEqual(
      ShareFileName.named("IMG_0001.HEIC", typeIdentifier: UTType.jpeg.identifier), "IMG_0001.HEIC")
  }

  func testTheMimeTypeFollowsTheNameBeforeTheType() {
    XCTAssertEqual(
      ShareFileName.mimeType(name: "clip.mov", typeIdentifier: UTType.data.identifier),
      "video/quicktime")
    XCTAssertEqual(
      ShareFileName.mimeType(name: "shared", typeIdentifier: UTType.pdf.identifier),
      "application/pdf")
  }
}

final class ShareInboxTests: XCTestCase {
  func testOnlyTheShareURLWakesTheInbox() {
    XCTAssertTrue(ShareInbox.isLaunch(URL(string: "im.zuno.chat://share")!))
    XCTAssertTrue(ShareInbox.isLaunch(ShareInbox.launchURL))
    XCTAssertFalse(ShareInbox.isLaunch(URL(string: "im.zuno.chat://room")!))
    XCTAssertFalse(ShareInbox.isLaunch(URL(string: "https://share")!))
  }
}

final class ShareItemKindTests: XCTestCase {
  func testAPhotoIsAFileOfItsFirstImageType() {
    XCTAssertEqual(ShareItemKind.of(["public.heic", "public.jpeg"]), .file("public.heic"))
  }

  func testALivePhotoSharesItsStillImage() {
    XCTAssertEqual(
      ShareItemKind.of(["public.jpeg", "com.apple.live-photo", "public.heic"]),
      .file("public.jpeg"))
  }

  func testVideoAndAudioAreFiles() {
    XCTAssertEqual(
      ShareItemKind.of(["com.apple.quicktime-movie"]), .file("com.apple.quicktime-movie"))
    XCTAssertEqual(ShareItemKind.of(["public.mp3"]), .file("public.mp3"))
  }

  func testAWebPageIsALinkEvenWhenTextComesWithIt() {
    XCTAssertEqual(ShareItemKind.of(["public.url"]), .link)
    XCTAssertEqual(ShareItemKind.of(["public.url", "public.plain-text"]), .link)
  }

  func testPlainOrRichTextIsText() {
    XCTAssertEqual(ShareItemKind.of(["public.utf8-plain-text"]), .text)
    XCTAssertEqual(
      ShareItemKind.of(["public.rtf", "com.apple.webarchive", "public.plain-text"]), .text)
  }

  func testADocumentIsAFileOfItsContentType() {
    XCTAssertEqual(ShareItemKind.of(["public.file-url", "com.adobe.pdf"]), .file("com.adobe.pdf"))
    XCTAssertEqual(ShareItemKind.of(["com.adobe.pdf"]), .file("com.adobe.pdf"))
    XCTAssertEqual(ShareItemKind.of(["public.vcard"]), .file("public.vcard"))
  }

  func testAFileURLWithoutAContentTypeIsLoadedByItsURL() {
    XCTAssertEqual(ShareItemKind.of(["public.file-url"]), .fileURL)
  }

  func testNothingUsableIsUnsupported() {
    XCTAssertEqual(ShareItemKind.of([]), .unsupported)
    XCTAssertEqual(ShareItemKind.of(["com.apple.live-photo"]), .unsupported)
    XCTAssertEqual(ShareItemKind.of(["com.apple.webarchive"]), .unsupported)
  }
}

final class ShareEntryTests: XCTestCase {
  private var base: URL!
  private var root: URL { base.appendingPathComponent("inbox", isDirectory: true) }

  override func setUpWithError() throws {
    base = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: base)
  }

  func testAFileIsCopiedIntoItsSlotAndListedInTheManifest() throws {
    var entry = try ShareEntry.create(in: root, id: "one")
    let source = try sample("IMG_0001.jpeg")

    entry.add(
      try ShareEntry.place(
        source, in: entry.directory, index: 0, typeIdentifier: UTType.jpeg.identifier))

    XCTAssertTrue(try entry.commit(created: Date(timeIntervalSince1970: 100)))
    XCTAssertEqual(
      try manifest(of: entry),
      ShareManifest(
        created: Date(timeIntervalSince1970: 100), text: nil,
        files: [.init(path: "0/IMG_0001.jpeg", name: "IMG_0001.jpeg", mimeType: "image/jpeg")]))
    XCTAssertTrue(exists(entry.directory.appendingPathComponent("0/IMG_0001.jpeg")))
    XCTAssertTrue(exists(source))
  }

  func testTextsAreJoinedInOrderWithoutBlanksOrRepeats() throws {
    var entry = try ShareEntry.create(in: root, id: "one")
    entry.add("https://example.org")
    entry.add("  ")
    entry.add("hello")
    entry.add("hello")

    XCTAssertTrue(try entry.commit(created: Date()))
    XCTAssertEqual(try manifest(of: entry).text, "https://example.org\nhello")
  }

  func testNothingToShareRemovesTheEntry() throws {
    let entry = try ShareEntry.create(in: root, id: "one")

    XCTAssertFalse(try entry.commit(created: Date()))
    XCTAssertFalse(exists(entry.directory))
  }

  func testImageDataIsNamedByItsType() throws {
    let entry = try ShareEntry.create(in: root, id: "one")

    let file = try ShareEntry.place(
      Data([1, 2, 3]), named: "shared", in: entry.directory, index: 2,
      typeIdentifier: UTType.png.identifier)

    XCTAssertEqual(
      file, ShareManifest.File(path: "2/shared.png", name: "shared.png", mimeType: "image/png"))
    XCTAssertTrue(exists(entry.directory.appendingPathComponent("2/shared.png")))
  }

  func testAFolderIsRefused() throws {
    let entry = try ShareEntry.create(in: root, id: "one")
    let folder = base.appendingPathComponent("Folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    XCTAssertThrowsError(
      try ShareEntry.place(
        folder, in: entry.directory, index: 0, typeIdentifier: UTType.folder.identifier))
    XCTAssertFalse(exists(entry.directory.appendingPathComponent("0/Folder")))
  }

  func testACopyLandingAfterCancelLeavesNothingBehind() throws {
    let entry = try ShareEntry.create(in: root, id: "one")
    let source = try sample("late.jpeg")
    entry.discard()

    XCTAssertThrowsError(
      try ShareEntry.place(
        source, in: entry.directory, index: 0, typeIdentifier: UTType.jpeg.identifier))
    XCTAssertFalse(exists(entry.directory))
  }

  func testTheInboxIsLeftOutOfBackups() throws {
    _ = try ShareEntry.create(in: root, id: "one")

    let values = try URL(fileURLWithPath: root.path).resourceValues(forKeys: [
      .isExcludedFromBackupKey
    ])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  private func sample(_ name: String) throws -> URL {
    let url = base.appendingPathComponent(name)
    try Data([0xFF, 0xD8, 0xFF]).write(to: url)
    return url
  }

  private func manifest(of entry: ShareEntry) throws -> ShareManifest {
    try ShareManifest.decoded(
      from: Data(contentsOf: entry.directory.appendingPathComponent("manifest.json")))
  }
}

final class ShareInboxCollectorTests: XCTestCase {
  private var base: URL!
  private var inbox: URL { base.appendingPathComponent("inbox", isDirectory: true) }
  private var imports: URL { base.appendingPathComponent("imports", isDirectory: true) }
  private var collector: ShareInboxCollector {
    ShareInboxCollector(inbox: inbox, imports: imports)
  }
  private let now = Date()

  override func setUpWithError() throws {
    base = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: base)
  }

  func testAFreshShareMovesOutOfTheInboxAndIsHandedOver() throws {
    try share("one", created: now.addingTimeInterval(-5), text: "hi", file: "a.pdf")

    let payload = try XCTUnwrap(collector.collect(now: now))

    XCTAssertEqual(payload.text, "hi")
    XCTAssertEqual(payload.files.map(\.name), ["a.pdf"])
    XCTAssertEqual(payload.files.map(\.mimeType), ["application/pdf"])
    let url = try XCTUnwrap(URL(string: payload.files[0].uri))
    XCTAssertTrue(url.isFileURL)
    XCTAssertEqual(url.path, imports.appendingPathComponent("one/0/a.pdf").path)
    XCTAssertTrue(exists(url))
    XCTAssertFalse(exists(inbox.appendingPathComponent("one")))
  }

  func testAShareIsHandedOverOnce() throws {
    try share("one", created: now, text: "hi")

    XCTAssertNotNil(collector.collect(now: now))
    XCTAssertNil(collector.collect(now: now))
  }

  func testAShareOlderThanTheWindowIsDroppedNotOffered() throws {
    try share("one", created: now.addingTimeInterval(-ShareInbox.freshness - 1), text: "hi")

    XCTAssertNil(collector.collect(now: now))
    XCTAssertFalse(exists(inbox.appendingPathComponent("one")))
  }

  func testTheNewestFreshShareWinsAndOlderOnesAreDropped() throws {
    try share("older", created: now.addingTimeInterval(-60), text: "first")
    try share("newer", created: now.addingTimeInterval(-10), text: "second")

    XCTAssertEqual(collector.collect(now: now)?.text, "second")
    XCTAssertFalse(exists(inbox.appendingPathComponent("older")))
    XCTAssertNil(collector.collect(now: now))
  }

  func testAShareStillBeingWrittenIsLeftAlone() throws {
    let unfinished = inbox.appendingPathComponent("writing", isDirectory: true)
    try FileManager.default.createDirectory(at: unfinished, withIntermediateDirectories: true)

    XCTAssertNil(collector.collect(now: now))
    XCTAssertTrue(exists(unfinished))
  }

  func testAnUnfinishedShareLeftBehindIsCleanedUp() throws {
    var unfinished = inbox.appendingPathComponent("abandoned", isDirectory: true)
    try FileManager.default.createDirectory(at: unfinished, withIntermediateDirectories: true)
    try backdate(&unfinished, by: ShareInbox.freshness + 60)

    XCTAssertNil(collector.collect(now: now))
    XCTAssertFalse(exists(unfinished))
  }

  func testOldImportsAreClearedWhenAShareArrives() throws {
    var stale = imports.appendingPathComponent("stale", isDirectory: true)
    let recent = imports.appendingPathComponent("recent", isDirectory: true)
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
    try backdate(&stale, by: ShareInboxCollector.importLifetime + 60)
    try share("one", created: now, text: "hi")

    XCTAssertNotNil(collector.collect(now: now))
    XCTAssertFalse(exists(stale))
    XCTAssertTrue(exists(recent))
  }

  func testNoInboxMeansNothingToCollect() {
    XCTAssertNil(collector.collect(now: now))
  }

  func testAShareThatCannotMoveStaysForTheNextTry() throws {
    try share("one", created: now, text: "hi")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try Data().write(to: imports)

    XCTAssertNil(collector.collect(now: now))
    XCTAssertTrue(exists(inbox.appendingPathComponent("one/manifest.json")))

    try FileManager.default.removeItem(at: imports)
    XCTAssertEqual(collector.collect(now: now)?.text, "hi")
  }

  func testTheSweepKeepsFreshSharesAndDropsStaleOnes() throws {
    try share("fresh", created: now.addingTimeInterval(-30), text: "new")
    try share("stale", created: now.addingTimeInterval(-ShareInbox.freshness - 1), text: "old")

    let kept = ShareInbox.sweep(inbox, now: now)

    XCTAssertEqual(kept.map(\.directory.lastPathComponent), ["fresh"])
    XCTAssertEqual(kept.first?.manifest.text, "new")
    XCTAssertFalse(exists(inbox.appendingPathComponent("stale")))
  }

  private func share(_ id: String, created: Date, text: String? = nil, file: String? = nil)
    throws
  {
    var entry = try ShareEntry.create(in: inbox, id: id)
    if let text { entry.add(text) }
    if let file {
      let source = base.appendingPathComponent(file)
      try Data("x".utf8).write(to: source)
      entry.add(
        try ShareEntry.place(
          source, in: entry.directory, index: 0, typeIdentifier: UTType.data.identifier))
    }
    XCTAssertTrue(try entry.commit(created: created))
  }

  private func backdate(_ url: inout URL, by interval: TimeInterval) throws {
    var values = URLResourceValues()
    values.creationDate = now.addingTimeInterval(-interval)
    try url.setResourceValues(values)
    url = URL(fileURLWithPath: url.path, isDirectory: true)
  }
}

final class ShareCacheTests: XCTestCase {
  private var cache: ShareCache!

  override func setUpWithError() throws {
    cache = ShareCache(
      root: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true))
  }

  override func tearDownWithError() throws {
    cache.clear()
  }

  func testImportedFilesMoveIntoNumberedSlotsInOrder() throws {
    let first = try imported("x/0/a.jpg")
    let second = try imported("x/1/b.pdf")

    let paths = cache.move(
      uris: [first.absoluteString, second.absoluteString], names: ["a.jpg", "b/../c.pdf"])

    XCTAssertEqual(paths.count, 2)
    XCTAssertEqual(paths[0].map { URL(fileURLWithPath: $0).lastPathComponent }, "a.jpg")
    XCTAssertEqual(paths[1].map { URL(fileURLWithPath: $0).lastPathComponent }, "b_.._c.pdf")
    XCTAssertEqual(
      paths[1].map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }, "1")
    XCTAssertTrue(paths.allSatisfy { $0.map { exists(URL(fileURLWithPath: $0)) } ?? false })
    XCTAssertFalse(exists(first))
    XCTAssertFalse(exists(second))
  }

  func testOnlyFilesHandedOverFromTheInboxMove() throws {
    let outside = cache.root.deletingLastPathComponent().appendingPathComponent(
      "\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    let missing = cache.imports.appendingPathComponent("x/0/gone.txt")
    let kept = try imported("x/2/kept.txt")

    let paths = cache.move(
      uris: [outside.absoluteString, "content://a/1", missing.absoluteString, kept.absoluteString],
      names: ["a.txt", "b.txt", "gone.txt", "kept.txt"])

    XCTAssertEqual(paths.prefix(3).compactMap { $0 }, [])
    XCTAssertNotNil(paths[3])
    XCTAssertTrue(exists(outside))
  }

  func testACopyRequestNeedsUrisAndNames() {
    let request = ShareCache.request(from: ["uris": ["file:///a"], "names": ["a"]])

    XCTAssertEqual(request?.uris, ["file:///a"])
    XCTAssertEqual(request?.names, ["a"])
    XCTAssertNil(ShareCache.request(from: nil))
    XCTAssertNil(ShareCache.request(from: ["uris": ["file:///a"]]))
    XCTAssertNil(ShareCache.request(from: ["uris": "file:///a", "names": ["a"]]))
  }

  func testTheChannelValueLeavesOutWhatIsMissing() {
    let value = SharePayload(
      text: nil, files: [.init(uri: "file:///a", name: "a", mimeType: nil)]
    ).channelValue
    let files = value["files"] as? [[String: Any]]

    XCTAssertNil(value["text"])
    XCTAssertEqual(files?.first?["uri"] as? String, "file:///a")
    XCTAssertEqual(files?.first?["name"] as? String, "a")
    XCTAssertNil(files?.first?["mimeType"])
  }

  private func imported(_ path: String) throws -> URL {
    let url = cache.imports.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: url)
    return url
  }
}

private func exists(_ url: URL) -> Bool {
  FileManager.default.fileExists(atPath: url.path)
}
