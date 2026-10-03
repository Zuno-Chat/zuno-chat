import CryptoKit
import XCTest

@testable import Runner

final class NotifyStoreTests: XCTestCase {
  private var directory: URL!
  private var store: NotifyStore!
  private let key = SymmetricKey(size: .bits256)

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = try makeTemporaryDirectory().appendingPathComponent("zuno-nse")
    store = NotifyStore(directory: directory)
    try store.prepare()
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    super.tearDown()
  }

  func testTheGroupComesFromTheInfoPlistKey() {
    XCTAssertEqual(NotifyStore.groupInfoKey, "ZunoNotifyGroup")
    XCTAssertNotNil(NotifyStore.groupIdentifier())
  }

  func testTheDirectoryIsLeftOutOfBackups() throws {
    let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])

    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  func testAWrittenFileReadsBackAndIsSealedUnderItsName() throws {
    let plaintext = Data(#"{"v":1}"#.utf8)

    try store.write("meta", plaintext: plaintext, key: key)

    XCTAssertEqual(store.read("meta", key: key), .found(plaintext))
    let raw = try Data(contentsOf: store.url("meta"))
    XCTAssertEqual(try SealedFile.open(raw, name: "meta", key: key), plaintext)
  }

  func testAMissingFileIsMissingAndAForeignOneIsCorrupt() throws {
    XCTAssertEqual(store.read("meta", key: key), .missing)

    try Data("plain".utf8).write(to: store.url("meta"))

    XCTAssertEqual(store.read("meta", key: key), .corrupt)
  }

  func testAFileSealedUnderAnotherKeyIsCorrupt() throws {
    try store.write("ledger", plaintext: Data("{}".utf8), key: key)

    XCTAssertEqual(store.read("ledger", key: SymmetricKey(size: .bits256)), .corrupt)
  }

  func testRoomFilesLiveInTheirOwnFolder() throws {
    try store.write(NotifyFile.room("abc"), plaintext: Data("{}".utf8), key: key)

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("rooms/abc").path))
  }

  func testAnUnchangedFileIsNotWrittenAgain() throws {
    XCTAssertTrue(try store.writeIfChanged("meta", plaintext: Data("{}".utf8), key: key))
    let first = try Data(contentsOf: store.url("meta"))

    XCTAssertFalse(try store.writeIfChanged("meta", plaintext: Data("{}".utf8), key: key))
    XCTAssertEqual(try Data(contentsOf: store.url("meta")), first)
    XCTAssertTrue(try store.writeIfChanged("meta", plaintext: Data("{ }".utf8), key: key))
  }

  func testWritesLeaveNoTemporaryFilesBehind() throws {
    for index in 0..<5 {
      try store.write("meta", plaintext: Data("\(index)".utf8), key: key)
    }

    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") })
  }

  func testTheRingFlagIsOneUnsealedByte() throws {
    try store.writeRingFlag(false)
    XCTAssertEqual(try Data(contentsOf: store.url(NotifyFile.ringFlag)), Data([0x30]))
    XCTAssertEqual(store.readRingFlag(), false)

    try store.writeRingFlag(true)
    XCTAssertEqual(store.readRingFlag(), true)
  }

  func testAMissingOrStrangeRingFlagReadsAsUnknown() throws {
    XCTAssertNil(store.readRingFlag())

    try Data([0x37, 0x37]).write(to: store.url(NotifyFile.ringFlag))

    XCTAssertNil(store.readRingFlag())
  }

  func testTheSignedOutMarkerComesAndGoes() throws {
    XCTAssertEqual(store.signedOut(), .absent)

    try store.markSignedOut()
    XCTAssertEqual(store.signedOut(), .present)

    store.clearSignedOut()
    XCTAssertEqual(store.signedOut(), .absent)
  }

  func testWipingRemovesEverythingButTheSignedOutMarker() throws {
    try store.write("meta", plaintext: Data("{}".utf8), key: key)
    try store.write(NotifyFile.room("abc"), plaintext: Data("{}".utf8), key: key)
    try store.writeRingFlag(true)
    try store.markSignedOut()

    store.wipe()

    XCTAssertEqual(store.read("meta", key: key), .missing)
    XCTAssertEqual(store.read(NotifyFile.room("abc"), key: key), .missing)
    XCTAssertNil(store.readRingFlag())
    XCTAssertEqual(store.signedOut(), .present)
    try store.write(NotifyFile.room("def"), plaintext: Data("{}".utf8), key: key)
  }
}

final class DeliveryLogTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = try makeTemporaryDirectory()
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  func testALineCarriesTheTimeTheEventAndItsFields() {
    let log = DeliveryLog(url: directory.appendingPathComponent("log.app"))

    log.append("ring", [("t", "2d2de6b6"), ("ms", "42")], at: Date(timeIntervalSince1970: 0))

    XCTAssertEqual(log.lines(), ["1970-01-01T00:00:00.000Z ring t=2d2de6b6 ms=42"])
  }

  func testSpacesAndNewlinesCannotForgeAnotherLine() {
    let log = DeliveryLog(url: directory.appendingPathComponent("log.app"))

    log.append("odd event", [("k ey", "va\nlue")], at: Date(timeIntervalSince1970: 0))

    XCTAssertEqual(log.lines(), ["1970-01-01T00:00:00.000Z odd_event k_ey=va_lue"])
  }

  func testTheLogKeepsItsNewestTwoHundredLines() {
    let log = DeliveryLog(url: directory.appendingPathComponent("log.app"))

    for index in 0..<205 {
      log.append("ring", [("n", "\(index)")])
    }

    let lines = log.lines()
    XCTAssertEqual(lines.count, 200)
    XCTAssertTrue(lines[0].hasSuffix("ring n=5"))
    XCTAssertTrue(lines[199].hasSuffix("ring n=204"))
  }

  func testAMissingLogHasNoLines() {
    XCTAssertEqual(DeliveryLog(url: directory.appendingPathComponent("none")).lines(), [])
  }
}

final class DarwinHintTests: XCTestCase {
  func testTheHintsCarryTheContractNames() {
    XCTAssertEqual(DarwinHint.ringChanged.rawValue, "im.zuno.chat.ring.changed")
    XCTAssertEqual(DarwinHint.callsChanged.rawValue, "im.zuno.chat.calls.changed")
    XCTAssertEqual(DarwinHint.readModelChanged.rawValue, "im.zuno.chat.readmodel.changed")
  }

  func testAPostedHintReachesItsObserverAndNotOthers() {
    let heard = expectation(description: "ring hint")
    let unheard = expectation(description: "calls hint")
    unheard.isInverted = true
    let ring = DarwinHintCenter.shared.observe(.ringChanged) { heard.fulfill() }
    let calls = DarwinHintCenter.shared.observe(.callsChanged) { unheard.fulfill() }
    defer {
      DarwinHintCenter.shared.remove(ring)
      DarwinHintCenter.shared.remove(calls)
    }

    DarwinHint.ringChanged.post()

    wait(for: [heard], timeout: 30)
    wait(for: [unheard], timeout: 0.5)
  }

  func testARemovedObserverHearsNothing() {
    let unheard = expectation(description: "removed")
    unheard.isInverted = true
    let token = DarwinHintCenter.shared.observe(.readModelChanged) { unheard.fulfill() }

    DarwinHintCenter.shared.remove(token)
    DarwinHint.readModelChanged.post()

    wait(for: [unheard], timeout: 0.5)
  }
}

final class ReadModelFilesTests: XCTestCase {
  func testPhaseTwoMetaDecodesWithTheFullLevelByDefault() throws {
    let meta = try XCTUnwrap(
      NotifyMeta.decoded(
        Data(
          #"{"v":1,"user":"@me:zuno.im","device":"PHONE","server_offset_ms":1000,"ringtone":false,"voip_current":true,"heartbeat_ms":7}"#
            .utf8)))

    XCTAssertEqual(
      meta,
      NotifyMeta(
        user: "@me:zuno.im", device: "PHONE", serverOffsetMs: 1_000, ringtone: false,
        voipCurrent: true, heartbeatMs: 7, level: .full))
  }

  func testALevelIsReadWhenPresentAndAnyOtherPresentValueReadsAsNothing() {
    let none = NotifyMeta.decoded(
      Data(
        #"{"v":1,"user":"@me:zuno.im","device":"D","ringtone":true,"heartbeat_ms":1,"level":"none"}"#
          .utf8))
    let absent = NotifyMeta.decoded(Data(#"{"v":1,"user":"@me:zuno.im","device":"D"}"#.utf8))

    XCTAssertEqual(none?.level, PreviewLevel.none)
    XCTAssertNil(none?.serverOffsetMs)
    XCTAssertEqual(absent?.level, PreviewLevel.full)
    for level in [#""later""#, "7", "null"] {
      let odd = NotifyMeta.decoded(
        Data(#"{"v":1,"user":"@me:zuno.im","device":"D","level":\#(level)}"#.utf8))

      XCTAssertEqual(odd?.level, PreviewLevel.none, level)
    }
  }

  func testMetaOfAnotherVersionOrWithoutItsUserIsNoMeta() {
    XCTAssertNil(NotifyMeta.decoded(Data(#"{"v":2,"user":"@me:zuno.im","device":"D"}"#.utf8)))
    XCTAssertNil(NotifyMeta.decoded(Data(#"{"v":1,"device":"D"}"#.utf8)))
  }

  func testARoomFileIsReadOnlyForTheRoomItNames() {
    let json = Data(
      #"{"v":1,"room":"!abc:zuno.im","title":"Alice","dm":true,"partner":"Alice"}"#.utf8)

    XCTAssertEqual(
      RoomTitleFile.decoded(json, roomId: "!abc:zuno.im"),
      RoomTitleFile(room: "!abc:zuno.im", title: "Alice", dm: true, partner: "Alice"))
    XCTAssertNil(RoomTitleFile.decoded(json, roomId: "!other:zuno.im"))
  }

  func testFileNamesFollowTheContract() {
    XCTAssertEqual(NotifyFile.meta, "meta")
    XCTAssertEqual(NotifyFile.ledger, "ledger")
    XCTAssertEqual(NotifyFile.ringFlag, "ring.flag")
    XCTAssertEqual(NotifyFile.signedOut, "signed_out")
    XCTAssertEqual(NotifyFile.room("2d2d"), "rooms/2d2d")
  }
}
