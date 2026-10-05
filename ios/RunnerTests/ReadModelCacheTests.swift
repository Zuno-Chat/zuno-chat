import CryptoKit
@preconcurrency import Flutter
import XCTest

@testable import Runner

@MainActor
final class ReadModelFixture {
  let directory: URL
  let memory = MemoryKeychain()
  let store: NotifyStore

  init(_ test: XCTestCase) throws {
    let directory = try makeTemporaryDirectory()
    self.directory = directory
    store = NotifyStore(directory: directory.appendingPathComponent("zuno-nse"))
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
  }

  func cache() -> ReadModelCache {
    ReadModelCache(
      store: store, keychain: NotifyKeychain(accessGroup: nil, backend: memory), now: { 42 })
  }
}

@MainActor
final class ReadModelCacheTests: XCTestCase {
  private let meta =
    #"{"v":1,"user":"@me:zuno.im","device":"PHONE","server_offset_ms":1000,"ringtone":false,"voip_current":true,"heartbeat_ms":7}"#
  private let room = #"{"v":1,"room":"!abc:zuno.im","title":"Alice","dm":true,"partner":"Alice"}"#

  func testMetaWrittenFromDartIsReadBackAndCopiesTheRingtoneToTheFlag() throws {
    let fixture = try ReadModelFixture(self)
    let cache = fixture.cache()

    try cache.writeMeta(Data(meta.utf8))

    XCTAssertEqual(cache.meta()?.user, "@me:zuno.im")
    XCTAssertEqual(fixture.store.readRingFlag(), false)
    XCTAssertEqual(fixture.cache().meta()?.serverOffsetMs, 1_000)
  }

  func testMetaThatIsNotPhaseTwoMetaIsRefused() throws {
    XCTAssertThrowsError(try ReadModelFixture(self).cache().writeMeta(Data(#"{"v":1}"#.utf8)))
  }

  func testARoomFileIsStoredUnderTheRoomTokenAndReadBackForThatRoom() throws {
    let fixture = try ReadModelFixture(self)
    let cache = fixture.cache()

    try cache.writeRoom(roomId: "!abc:zuno.im", json: Data(room.utf8))

    XCTAssertEqual(cache.room("!abc:zuno.im")?.partner, "Alice")
    let token = try XCTUnwrap(cache.roomToken("!abc:zuno.im"))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: fixture.store.url(NotifyFile.room(token)).path))
    XCTAssertEqual(fixture.cache().room("!abc:zuno.im")?.title, "Alice")
  }

  func testARoomFileNamingAnotherRoomIsRefused() throws {
    let cache = try ReadModelFixture(self).cache()

    XCTAssertThrowsError(try cache.writeRoom(roomId: "!other:zuno.im", json: Data(room.utf8)))
  }

  func testADeletedRoomFileIsGone() throws {
    let fixture = try ReadModelFixture(self)
    let cache = fixture.cache()
    try cache.writeRoom(roomId: "!abc:zuno.im", json: Data(room.utf8))

    cache.deleteRoom(roomId: "!abc:zuno.im")

    XCTAssertNil(cache.room("!abc:zuno.im"))
    XCTAssertNil(fixture.cache().room("!abc:zuno.im"))
  }

  func testLedgerChangesArePersistedUnderTheRoomToken() throws {
    let fixture = try ReadModelFixture(self)
    let cache = fixture.cache()
    let identity = CallIdentity.uuid(roomId: "!abc:zuno.im", callId: "c1")
    _ = cache.secrets(create: true)

    cache.record(
      CallLedgerChange(identity: identity, roomId: "!abc:zuno.im", state: .ringing, source: .push))
    cache.record(
      CallLedgerChange(identity: identity, roomId: "!abc:zuno.im", state: .declined, source: .push))

    let entry = try XCTUnwrap(fixture.cache().ledger().entry(for: identity))
    XCTAssertEqual(entry.state, .declined)
    XCTAssertEqual(entry.t, cache.roomToken("!abc:zuno.im"))
    XCTAssertEqual(entry.ts, 42)
  }

  func testAFreshKeychainItemThrowsAwayFilesSealedUnderTheOldOne() throws {
    let fixture = try ReadModelFixture(self)
    try fixture.cache().writeMeta(Data(meta.utf8))
    fixture.memory.store(
      Data("junk".utf8), service: NotifyKeychain.service, account: NotifyKeychain.account)

    let cache = fixture.cache()
    guard case .created = cache.secrets(create: true) else { return XCTFail("no new item") }

    XCTAssertNil(cache.meta())
    XCTAssertEqual(
      fixture.store.read(NotifyFile.meta, key: SymmetricKey(size: .bits256)), .missing)
  }

  func testBeforeFirstUnlockNothingIsReadOrWritten() throws {
    let fixture = try ReadModelFixture(self)
    fixture.memory.locked = true
    let cache = fixture.cache()

    XCTAssertNil(cache.meta())
    XCTAssertNil(cache.roomToken("!abc:zuno.im"))
    XCTAssertEqual(cache.ledger(), Ledger())
    XCTAssertThrowsError(try cache.writeMeta(Data(meta.utf8)))
  }

  func testWipingDropsTheItemAndTheFilesButNotTheSignedOutMarker() throws {
    let fixture = try ReadModelFixture(self)
    let cache = fixture.cache()
    try cache.writeMeta(Data(meta.utf8))
    cache.setSignedOut(true)

    cache.wipe()

    XCTAssertNil(
      fixture.memory.stored(service: NotifyKeychain.service, account: NotifyKeychain.account))
    XCTAssertNil(cache.meta())
    XCTAssertEqual(cache.signedOut(), .present)
    cache.setSignedOut(false)
    XCTAssertEqual(cache.signedOut(), .absent)
  }

  func testTheThreadKeyIsTheOpaqueRoomToken() throws {
    let cache = try ReadModelFixture(self).cache()
    let key = try XCTUnwrap(cache.threadKey(roomId: "!abc:zuno.im"))

    guard case .ready(let secrets) = cache.secrets(create: false) else { return XCTFail("no item") }
    XCTAssertEqual(key, OpaqueIds.roomToken("!abc:zuno.im", installKey: secrets.tokenKey))
  }
}

@MainActor
final class NsePluginTests: XCTestCase {
  private func plugin() throws -> (NsePlugin, ReadModelCache) {
    let cache = try ReadModelFixture(self).cache()
    return (NsePlugin(cache: cache), cache)
  }

  private func call(_ plugin: NsePlugin, _ method: String, _ arguments: [String: Any]? = nil)
    -> Any?
  {
    var reply: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { reply = $0 }
    return reply
  }

  func testWritesFromDartLandInTheReadModel() throws {
    let (plugin, cache) = try plugin()

    XCTAssertNil(
      call(
        plugin, "writeMeta",
        ["json": #"{"v":1,"user":"@me:zuno.im","device":"D","ringtone":true,"heartbeat_ms":1}"#]))
    XCTAssertNil(
      call(
        plugin, "writeRoom",
        [
          "room_id": "!abc:zuno.im",
          "json": #"{"v":1,"room":"!abc:zuno.im","title":"Room","dm":false,"partner":""}"#,
        ]))

    XCTAssertEqual(cache.meta()?.user, "@me:zuno.im")
    XCTAssertEqual(cache.room("!abc:zuno.im")?.title, "Room")
  }

  func testTheThreadKeyIsReturnedForARoom() throws {
    let (plugin, cache) = try plugin()

    XCTAssertEqual(
      call(plugin, "threadKey", ["room_id": "!abc:zuno.im"]) as? String,
      cache.roomToken("!abc:zuno.im"))
  }

  func testAWriteNativeCodeCannotReadIsRefused() throws {
    let (plugin, _) = try plugin()

    XCTAssertEqual(
      (call(plugin, "writeMeta", ["json": "{}"]) as? FlutterError)?.code, "write_failed")
    XCTAssertEqual((call(plugin, "writeRoom", ["json": "{}"]) as? FlutterError)?.code, "bad_args")
  }

  func testDeleteAndWipeAnswerNothing() throws {
    let (plugin, _) = try plugin()

    XCTAssertNil(call(plugin, "deleteRoom", ["room_id": "!abc:zuno.im"]))
    XCTAssertNil(call(plugin, "wipe"))
  }

  func testAnUnknownMethodIsNotImplemented() throws {
    let (plugin, _) = try plugin()

    XCTAssertTrue((call(plugin, "unknown") as AnyObject) === FlutterMethodNotImplemented)
  }
}
