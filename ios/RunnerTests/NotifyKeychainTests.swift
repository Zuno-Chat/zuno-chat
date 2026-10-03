import CryptoKit
import Security
import XCTest

@testable import Runner

final class NotifyKeychainTests: XCTestCase {
  private var memory: MemoryKeychain!
  private var keychain: NotifyKeychain!

  override func setUp() {
    super.setUp()
    memory = MemoryKeychain()
    keychain = NotifyKeychain(accessGroup: "group.im.zuno.chat.notify.TEAM", backend: memory)
  }

  func testAMissingItemIsCreatedWithTwoFreshKeysAndThenReadBack() throws {
    guard case .created(let created) = keychain.load(createIfMissing: true) else {
      return XCTFail("the item was not created")
    }

    XCTAssertEqual(created.rmKey.count, 32)
    XCTAssertEqual(created.installKey.count, 32)
    XCTAssertNotEqual(created.rmKey, created.installKey)
    XCTAssertEqual(keychain.load(createIfMissing: true), .ready(created))
  }

  func testTheItemIsStoredUnderItsContractNames() throws {
    guard case .created(let created) = keychain.load(createIfMissing: true) else {
      return XCTFail("the item was not created")
    }
    let stored = try XCTUnwrap(
      memory.stored(service: "im.zuno.chat.notify", account: "notify"))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])

    XCTAssertEqual(json["rm_key"] as? String, created.rmKey.base64EncodedString())
    XCTAssertEqual(json["install_key"] as? String, created.installKey.base64EncodedString())
  }

  func testBeforeFirstUnlockItReportsLockedAndCreatesNothing() {
    memory.locked = true

    XCTAssertEqual(keychain.load(createIfMissing: true), .locked)
    memory.locked = false
    XCTAssertNil(memory.stored(service: "im.zuno.chat.notify", account: "notify"))
  }

  func testAMissingItemIsNotCreatedWhenOnlyReading() {
    XCTAssertEqual(keychain.load(createIfMissing: false), .unavailable)
  }

  func testAnUnreadableItemIsReplacedLikeAMissingOne() {
    memory.store(Data("not json".utf8), service: "im.zuno.chat.notify", account: "notify")

    guard case .created = keychain.load(createIfMissing: true) else {
      return XCTFail("the broken item was not replaced")
    }
  }

  func testDeletingLeavesNothingToRead() {
    _ = keychain.load(createIfMissing: true)

    keychain.delete()

    XCTAssertEqual(keychain.load(createIfMissing: false), .unavailable)
  }
}

final class SystemKeychainTests: XCTestCase {
  private let service = "im.zuno.chat.test.\(UUID().uuidString)"

  override func tearDown() {
    _ = SystemKeychain().delete(service: service, accessGroup: nil)
    super.tearDown()
  }

  func testAnItemIsAddedReadReplacedAndDeleted() {
    let keychain = SystemKeychain()

    XCTAssertEqual(keychain.read(service: service, account: "a", accessGroup: nil), .missing)
    XCTAssertEqual(
      keychain.write(Data("one".utf8), service: service, account: "a", accessGroup: nil),
      errSecSuccess)
    XCTAssertEqual(
      keychain.write(Data("two".utf8), service: service, account: "a", accessGroup: nil),
      errSecSuccess)
    XCTAssertEqual(
      keychain.read(service: service, account: "a", accessGroup: nil), .found(Data("two".utf8)))
    XCTAssertEqual(keychain.delete(service: service, accessGroup: nil), errSecSuccess)
    XCTAssertEqual(keychain.read(service: service, account: "a", accessGroup: nil), .missing)
  }

  func testDeletingAServiceLeavesOtherServicesAlone() {
    let keychain = SystemKeychain()
    let other = service + ".other"
    defer { _ = keychain.delete(service: other, accessGroup: nil) }
    _ = keychain.write(Data("keep".utf8), service: other, account: "a", accessGroup: nil)
    _ = keychain.write(Data("drop".utf8), service: service, account: "a", accessGroup: nil)

    _ = keychain.delete(service: service, accessGroup: nil)

    XCTAssertEqual(
      keychain.read(service: other, account: "a", accessGroup: nil), .found(Data("keep".utf8)))
  }
}

final class VoipKeyStoreTests: XCTestCase {
  private var memory: MemoryKeychain!

  override func setUp() {
    super.setUp()
    memory = MemoryKeychain()
  }

  private func store(_ next: [UInt32]) -> VoipKeyStore {
    let queue = KidQueue(next)
    return VoipKeyStore(backend: memory, newKid: { queue.next() })
  }

  func testTheFirstReadCreatesAKeyUnderTheVoipService() throws {
    guard case .ready(let keys) = store([7]).current() else { return XCTFail("no key") }

    XCTAssertEqual(keys.kid, 7)
    XCTAssertEqual(keys.key.count, 32)
    XCTAssertNotNil(memory.stored(service: "im.zuno.chat.voip", account: "voip"))
  }

  func testAZeroKidIsNeverUsed() {
    guard case .ready(let keys) = store([0, 0, 9]).current() else { return XCTFail("no key") }

    XCTAssertEqual(keys.kid, 9)
  }

  func testRotationKeepsThePreviousKeyUntilTheNewOneIsAcknowledged() throws {
    let keys = store([1, 1, 2])
    guard case .ready(let first) = keys.current() else { return XCTFail("no key") }

    let rotated = try XCTUnwrap(keys.rotate())

    XCTAssertEqual(rotated.kid, 2)
    XCTAssertEqual(rotated.prevKid, 1)
    XCTAssertEqual(rotated.prevKey, first.key)
    XCTAssertNil(rotated.prevUntilMs)
    XCTAssertNotNil(rotated.key(for: 1, nowMs: .max - 1))
  }

  func testAnAcknowledgementGivesThePreviousKeyTwentyFourMoreHours() throws {
    let keys = store([1, 2])
    _ = keys.current()
    _ = keys.rotate()

    let acknowledged = try XCTUnwrap(keys.acknowledge(kid: 2, nowMs: 1_000))

    XCTAssertEqual(acknowledged.prevUntilMs, 1_000 + 86_400_000)
    XCTAssertNotNil(acknowledged.key(for: 1, nowMs: 86_400_999))
    XCTAssertNil(acknowledged.key(for: 1, nowMs: 86_401_000))
  }

  func testAnAcknowledgementForAnotherKidChangesNothing() {
    let keys = store([1, 2])
    _ = keys.current()
    _ = keys.rotate()

    XCTAssertNil(keys.acknowledge(kid: 1, nowMs: 1_000))
    guard case .ready(let stored) = keys.load() else { return XCTFail("no key") }
    XCTAssertNil(stored.prevUntilMs)
  }

  func testAnUnknownKidHasNoKey() {
    guard case .ready(let keys) = store([5]).current() else { return XCTFail("no key") }

    XCTAssertNil(keys.key(for: 6, nowMs: 0))
  }

  func testBeforeFirstUnlockTheKeyIsLocked() {
    memory.locked = true

    XCTAssertEqual(store([5]).current(), .locked)
  }

  func testDeletingTheKeyMeansTheNextReadMakesANewOne() {
    let keys = store([5, 6])
    _ = keys.current()

    keys.delete()

    XCTAssertEqual(keys.load(), .missing)
    guard case .ready(let fresh) = keys.current() else { return XCTFail("no key") }
    XCTAssertEqual(fresh.kid, 6)
  }
}

final class KidQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var kids: [UInt32]

  init(_ kids: [UInt32]) {
    self.kids = kids
  }

  func next() -> UInt32 {
    lock.lock()
    defer { lock.unlock() }
    return kids.isEmpty ? UInt32.random(in: 1...UInt32.max) : kids.removeFirst()
  }
}
