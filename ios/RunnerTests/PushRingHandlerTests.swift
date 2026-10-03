@preconcurrency import CallKit
import CryptoKit
@preconcurrency import Flutter
import XCTest

@testable import Runner

@MainActor
final class Counter {
  var value = 0
}

@MainActor
final class RingFixture {
  static let placeholder = UUID(uuidString: "00000000-0000-4000-8000-000000000009")!
  static let now = Date(timeIntervalSince1970: 1_790_000_001)

  let read: ReadModelFixture
  let harness = CallKitHarness()
  let cache: ReadModelCache
  let handler: PushRingHandler
  let prewarmCount = Counter()
  var reported: [RingReported] = []

  var prewarms: Int { prewarmCount.value }

  init(_ test: XCTestCase) throws {
    read = try ReadModelFixture(test)
    cache = read.cache()
    let prewarmCount = prewarmCount
    handler = PushRingHandler(
      calls: harness.center, cache: cache, keys: VoipKeyStore(backend: read.memory),
      prewarm: { prewarmCount.value += 1 }, now: { RingFixture.now },
      makeUUID: { RingFixture.placeholder },
      defaults: UserDefaults(suiteName: "push-ring-\(UUID().uuidString)")!)
    AppDelegate.wireCallKit(harness.center, to: cache)
    handler.onReported = { [unowned self] in self.reported.append($0) }
    read.memory.store(
      try JSONEncoder().encode(VoipKeys(kid: VoipBlobFixture.kid, key: Data(0x00...0x1f))),
      service: VoipKeyStore.service, account: VoipKeyStore.account)
    try cache.writeMeta(
      Data(
        #"{"v":1,"user":"@me:zuno.im","device":"PHONE","server_offset_ms":0,"ringtone":true,"voip_current":true,"heartbeat_ms":1}"#
          .utf8))
  }

  static func payload(_ blob: Data = VoipBlobFixture.seal()) -> [AnyHashable: Any] {
    ["z": blob.base64EncodedString(), "event_id": "$z"]
  }

  static func forged() -> Data {
    var blob = VoipBlobFixture.seal()
    blob[blob.count - 1] ^= 0x01
    return blob
  }

  func push(_ payload: [AnyHashable: Any], mustReport: Bool? = nil) -> PushCompletion {
    let completion = PushCompletion()
    handler.handle(payload: payload, mustReport: mustReport) { completion.done() }
    return completion
  }
}

@MainActor
final class PushRingHandlerTests: XCTestCase {
  private let uuid = CallIdentity.uuid(roomId: "!abc:zuno.im", callId: "c1")

  func testAFreshRingIsReportedBeforeTheHandlerReturnsAndCompletesFromTheReport() throws {
    let ring = try RingFixture(self)

    let completion = ring.push(RingFixture.payload())

    XCTAssertEqual(ring.harness.provider.reports.map(\.uuid), [uuid])
    XCTAssertEqual(ring.harness.provider.reports.first?.name, "Alice")
    XCTAssertFalse(completion.called)
    ring.harness.provider.complete()
    XCTAssertTrue(completion.called)
    XCTAssertEqual(ring.prewarms, 1)
    XCTAssertEqual(ring.reported, [RingReported(uuid: uuid, roomId: "!abc:zuno.im")])
    XCTAssertEqual(ring.cache.ledger().entry(for: uuid)?.state, .ringing)
  }

  func testEveryKindOfPushIsReportedBeforeTheHandlerReturns() throws {
    let ring = try RingFixture(self)
    let pushes: [[AnyHashable: Any]] = [
      RingFixture.payload(RingFixture.forged()),
      RingFixture.payload(VoipBlobFixture.seal(kid: 99)),
      RingFixture.payload(VoipBlobFixture.seal(version: 0x02)),
      RingFixture.payload(VoipBlobFixture.seal(expiry: 1_789_999_000)),
      ["event_id": "$z"],
      RingFixture.payload(),
    ]

    for (index, payload) in pushes.enumerated() {
      let before = ring.harness.provider.reports.count
      let completion = ring.push(payload)
      XCTAssertEqual(ring.harness.provider.reports.count, before + 1, "push \(index)")
      ring.harness.provider.complete(CXErrorCodeIncomingCallError(.callUUIDAlreadyExists))
      XCTAssertTrue(completion.called, "push \(index)")
    }
  }

  func testWhenTheSystemSaysNoReportIsNeededItCompletesAtOnce() throws {
    let ring = try RingFixture(self)

    let completion = ring.push(RingFixture.payload(RingFixture.forged()), mustReport: false)

    XCTAssertTrue(completion.called)
    XCTAssertTrue(ring.harness.provider.reports.isEmpty)
    XCTAssertTrue(ring.cache.log?.lines().last?.contains(" must=0") ?? false)
  }

  func testATamperedRingIsEndedAndLoggedAsForged() throws {
    let ring = try RingFixture(self)

    _ = ring.push(RingFixture.payload(RingFixture.forged()))
    ring.harness.provider.complete()

    XCTAssertEqual(ring.harness.provider.ended.map(\.0), [RingFixture.placeholder])
    XCTAssertTrue(ring.cache.log?.lines().last?.contains(" forged ") ?? false)
    XCTAssertTrue(ring.cache.log?.lines().last?.contains(" must=-") ?? false)
  }

  func testWithoutMetaAfterFirstUnlockTheRingIsEnded() throws {
    let ring = try RingFixture(self)
    ring.cache.wipe()

    _ = ring.push(RingFixture.payload())
    ring.harness.provider.complete()

    XCTAssertEqual(ring.harness.provider.ended.map(\.0), [RingFixture.placeholder])
    XCTAssertEqual(ring.prewarms, 0)
  }

  func testASignedOutPhoneEndsTheRing() throws {
    let ring = try RingFixture(self)
    ring.cache.setSignedOut(true)

    _ = ring.push(RingFixture.payload())
    ring.harness.provider.complete()

    XCTAssertEqual(ring.harness.provider.ended.map(\.1), [.remoteEnded])
  }

  func testAThirdUnknownKeyWithinTenMinutesIsEndedAndAsksOnceToRegisterAgain() throws {
    let ring = try RingFixture(self)
    let unknown = RingFixture.payload(VoipBlobFixture.seal(kid: 99))
    for _ in 0..<2 {
      _ = ring.push(unknown)
      ring.harness.provider.complete()
      ring.harness.center.endAll(reason: .remoteEnded)
    }

    _ = ring.push(unknown)
    ring.harness.provider.complete()

    XCTAssertEqual(ring.harness.provider.ended.last?.0, RingFixture.placeholder)
    XCTAssertEqual(ring.harness.provider.ended.last?.1, .failed)
    XCTAssertEqual(ring.handler.takeEvents(), ["keyMismatch"])
  }

  func testBeforeFirstUnlockARingIsGenericAndBindsOnceProtectedDataArrives() throws {
    let ring = try RingFixture(self)
    ring.read.memory.locked = true

    _ = ring.push(RingFixture.payload())
    ring.harness.provider.complete()

    XCTAssertEqual(ring.harness.provider.reports.first?.name, "Zuno call")
    XCTAssertEqual(ring.prewarms, 0)
    ring.read.memory.locked = false
    ring.handler.protectedDataBecameAvailable()
    XCTAssertEqual(ring.harness.provider.updates.last?.name, "Alice")
    XCTAssertEqual(ring.harness.provider.updates.last?.video, true)
    XCTAssertEqual(ring.prewarms, 1)
    XCTAssertEqual(ring.harness.center.snapshot().identities[uuid], RingFixture.placeholder)
  }

  func testBeforeFirstUnlockAForgedRingEndsOnceItCanBeChecked() throws {
    let ring = try RingFixture(self)
    ring.read.memory.locked = true
    _ = ring.push(RingFixture.payload(RingFixture.forged()))
    ring.harness.provider.complete()

    ring.read.memory.locked = false
    ring.handler.protectedDataBecameAvailable()

    XCTAssertEqual(ring.harness.provider.ended.map(\.0), [RingFixture.placeholder])
  }

  func testBeforeFirstUnlockARingUnderAnotherKeyIsLeftToDartAsAGenericRingOnceUnlocked() throws {
    let ring = try RingFixture(self)
    ring.read.memory.locked = true
    _ = ring.push(RingFixture.payload(VoipBlobFixture.seal(kid: 99)))
    ring.harness.provider.complete()

    ring.read.memory.locked = false
    ring.handler.protectedDataBecameAvailable()

    let replayed = ring.harness.center.takeEvents().compactMap {
      $0["arguments"] as? [String: Any]
    }
    XCTAssertEqual(replayed.first?["uuid"] as? String, RingFixture.placeholder.uuidString)
    XCTAssertEqual(replayed.first?["source"] as? String, "generic")
    XCTAssertTrue(ring.harness.provider.ended.isEmpty)
    XCTAssertEqual(ring.handler.takeEvents(), ["keyMismatch"])
    XCTAssertEqual(ring.prewarms, 1)
  }

  func testAResentRingForTheCallAlreadyRingingIsReportedAgainButRingsOnce() throws {
    let ring = try RingFixture(self)
    _ = ring.push(RingFixture.payload())
    ring.harness.provider.complete()

    let completion = ring.push(RingFixture.payload())
    ring.harness.provider.complete(CXErrorCodeIncomingCallError(.callUUIDAlreadyExists))

    XCTAssertTrue(completion.called)
    XCTAssertEqual(ring.harness.provider.reports.map(\.uuid), [uuid, uuid])
    XCTAssertTrue(ring.harness.provider.ended.isEmpty)
    XCTAssertEqual(ring.harness.center.snapshot().ringing, uuid)
    XCTAssertEqual(ring.cache.ledger().calls.count, 1)
    XCTAssertEqual(ring.prewarms, 1)
  }

  func testARingForACallDeclinedInAnEarlierRunIsEndedWithoutRinging() throws {
    let ring = try RingFixture(self)
    ring.cache.record(
      CallLedgerChange(identity: uuid, roomId: "!abc:zuno.im", state: .declined, source: .push))

    _ = ring.push(RingFixture.payload())
    ring.harness.provider.complete()

    XCTAssertEqual(ring.harness.provider.ended.map(\.0), [RingFixture.placeholder])
    XCTAssertEqual(ring.prewarms, 0)
    XCTAssertTrue(ring.reported.isEmpty)
  }

  func testANewTokenIsAnnouncedOnceAndAnInvalidationToo() throws {
    let ring = try RingFixture(self)

    ring.handler.tokenUpdated(Data([1, 2, 3]))
    ring.handler.tokenUpdated(Data([1, 2, 3]))
    ring.handler.tokenInvalidated()

    XCTAssertEqual(ring.handler.takeEvents(), ["token", "invalidated"])
    XCTAssertEqual(ring.handler.takeEvents(), [])
  }

  func testSigningOutDropsTheKeyMarksTheGroupAndEndsCalls() throws {
    let ring = try RingFixture(self)
    _ = ring.push(RingFixture.payload())
    ring.harness.provider.complete()

    ring.handler.setSignedIn(false)

    XCTAssertEqual(ring.cache.signedOut(), .present)
    XCTAssertEqual(VoipKeyStore(backend: ring.read.memory).load(), .missing)
    XCTAssertEqual(ring.harness.provider.ended.map(\.0), [uuid])
    ring.handler.setSignedIn(true)
    XCTAssertEqual(ring.cache.signedOut(), .absent)
  }

  func testWithoutCallKitNoVoipPushesAreAskedFor() throws {
    let ring = try RingFixture(self)
    let mac = PushRingHandler(
      calls: CallKitHarness(available: false).center, cache: ring.cache,
      keys: VoipKeyStore(backend: ring.read.memory), prewarm: {})

    XCTAssertEqual(mac.desiredPushTypes(), [])
    XCTAssertEqual(ring.handler.desiredPushTypes(), [.voIP])
  }
}

final class PushCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0

  var called: Bool {
    lock.lock()
    defer { lock.unlock() }
    return calls > 0
  }

  func done() {
    lock.lock()
    calls += 1
    lock.unlock()
  }
}

final class MissedCallNoticeTests: XCTestCase {
  func testTheMissedCallNoticeAsksToUnlockAfterARestart() {
    let request = MissedCallNotice.request()

    XCTAssertEqual(request.content.title, "Missed call")
    XCTAssertEqual(request.content.body, "Unlock this device after a restart to answer calls.")
    XCTAssertNil(request.trigger)
  }
}
