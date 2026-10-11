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
  private func data(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
  }

  func testMetaReadsEveryField() throws {
    let meta = try XCTUnwrap(
      NotifyMeta.decoded(
        data([
          "v": 1, "user": "@mwong:zuno.im", "device": "D", "server_offset_ms": 1_000,
          "ringtone": false, "voip_current": true, "heartbeat_ms": 1_790_000_000_000,
          "base_url": "https://zuno.im", "level": "name", "notify": "mentions", "tone": false,
          "unread": ["t1", "t2"], "asked": ["!knock:zuno.im"],
          "mention": [
            "mxid": "@mwong:zuno.im", "display_name": "Mia",
            "keywords": [["pattern": "zuno", "highlight": true]],
            "rules": [".m.rule.roomnotif": false],
          ],
        ])))

    XCTAssertEqual(meta.user, "@mwong:zuno.im")
    XCTAssertEqual(meta.baseUrl, "https://zuno.im")
    XCTAssertEqual(meta.serverOffsetMs, 1_000)
    XCTAssertEqual(meta.level, .name)
    XCTAssertTrue(meta.mentionsOnly)
    XCTAssertFalse(meta.tone)
    XCTAssertFalse(meta.ringtone)
    XCTAssertEqual(meta.unread, ["t1", "t2"])
    XCTAssertEqual(meta.heartbeatMs, 1_790_000_000_000)
    XCTAssertEqual(meta.askedToJoin, ["!knock:zuno.im"])
    XCTAssertEqual(meta.mention?.keywords, [.init(pattern: "zuno", highlight: true)])
    XCTAssertEqual(meta.mention?.rules, [".m.rule.roomnotif": false])
  }

  func testAMetaWithOnlyItsUserIsASessionWithEveryDefault() throws {
    let meta = try XCTUnwrap(NotifyMeta.decoded(data(["v": 1, "user": "@mwong:zuno.im"])))

    XCTAssertEqual(meta.baseUrl, "")
    XCTAssertNil(meta.serverOffsetMs)
    XCTAssertEqual(meta.level, .full)
    XCTAssertFalse(meta.mentionsOnly)
    XCTAssertTrue(meta.tone)
    XCTAssertTrue(meta.ringtone)
    XCTAssertNil(meta.unread)
    XCTAssertNil(meta.heartbeatMs)
    XCTAssertNil(meta.mention)
    XCTAssertTrue(meta.askedToJoin.isEmpty)
  }

  func testTheLevelIsReadFromTheMetaAndANonStringOneStillCountsAsStated() {
    let none = NotifyMeta.decoded(data(["v": 1, "user": "@me:zuno.im", "level": "none"]))

    XCTAssertEqual(none?.level, PreviewLevel.none)
    for level: Any in [7, NSNull()] {
      let odd = NotifyMeta.decoded(data(["v": 1, "user": "@me:zuno.im", "level": level]))

      XCTAssertEqual(odd?.level, PreviewLevel.none, "\(level)")
    }
  }

  func testAStatedLevelIsReadByNameAndAnythingElseStatedReadsAsNothing() {
    XCTAssertEqual(PreviewLevel(meta: "full", stated: true), .full)
    XCTAssertEqual(PreviewLevel(meta: "name", stated: true), .name)
    XCTAssertEqual(PreviewLevel(meta: "none", stated: true), PreviewLevel.none)
    for value in ["later", "", "Name", nil] {
      XCTAssertEqual(
        PreviewLevel(meta: value, stated: true), PreviewLevel.none, String(describing: value))
    }
  }

  func testALevelTheMetaNeverStatedReadsAsFull() {
    for value in ["none", nil] {
      XCTAssertEqual(
        PreviewLevel(meta: value, stated: false), .full, String(describing: value))
    }
  }

  func testMetaOfAnotherVersionOrWithoutItsUserIsNoMeta() {
    XCTAssertNil(NotifyMeta.decoded(data(["v": 2, "user": "@me:zuno.im", "base_url": "https://x"])))
    XCTAssertNil(NotifyMeta.decoded(data(["v": 1, "device": "D", "base_url": "https://x"])))
    XCTAssertNil(NotifyMeta.decoded(Data("not json".utf8)))
  }

  func testARoomFileIsReadOnlyForTheRoomItNames() {
    let json = Data(
      #"{"v":1,"room":"!abc:zuno.im","title":"Alice","dm":true,"partner":"Alice"}"#.utf8)

    XCTAssertEqual(
      NotifyRoomFile.decoded(json, roomId: "!abc:zuno.im"),
      NotifyRoomFile(room: "!abc:zuno.im", title: "Alice", dm: true, partner: "Alice"))
    XCTAssertNil(NotifyRoomFile.decoded(json, roomId: "!other:zuno.im"))
  }

  func testARoomFileKeepsItsSessionsAndNotifiers() throws {
    let room = try XCTUnwrap(
      NotifyRoomFile.decoded(
        data([
          "v": 1, "room": "!abc:zuno.im", "title": "Design team", "dm": false, "partner": "",
          "sessions": [
            [
              "session_id": "s1", "sender": "@alice:zuno.im", "sender_key": "k1",
              "first_index": 4, "pickle": "p1",
            ]
          ],
          "notifiers": ["@admin:zuno.im"],
        ])))

    XCTAssertEqual(room.title, "Design team")
    XCTAssertEqual(
      room.session("s1"),
      NseSession(
        sessionId: "s1", sender: "@alice:zuno.im", senderKey: "k1", firstIndex: 4, pickle: "p1"))
    XCTAssertNil(room.session("s2"))
    XCTAssertEqual(room.notifiers, ["@admin:zuno.im"])
  }

  func testARoomFileSkipsSessionsMissingAPickleOrIndex() throws {
    let room = try XCTUnwrap(
      NotifyRoomFile.decoded(
        data([
          "v": 1, "room": "!abc:zuno.im",
          "sessions": [
            ["session_id": "s1", "first_index": 0], ["session_id": "s2", "pickle": "p"],
          ],
        ])))

    XCTAssertTrue(room.sessions.isEmpty)
    XCTAssertEqual(room.title, "")
    XCTAssertFalse(room.dm)
    XCTAssertEqual(room.partner, "")
  }

  func testFileNamesFollowTheContract() {
    XCTAssertEqual(NotifyFile.meta, "meta")
    XCTAssertEqual(NotifyFile.ledger, "ledger")
    XCTAssertEqual(NotifyFile.ringFlag, "ring.flag")
    XCTAssertEqual(NotifyFile.signedOut, "signed_out")
    XCTAssertEqual(NotifyFile.room("2d2d"), "rooms/2d2d")
  }
}
