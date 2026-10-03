import XCTest

@testable import Runner

final class LedgerTests: XCTestCase {
  private let first = CallIdentity.uuid(roomId: "!a:zuno.im", callId: "c1")
  private let second = CallIdentity.uuid(roomId: "!a:zuno.im", callId: "c2")

  func testARecordedRingCanBeFoundAndIsNotYetResolved() {
    var ledger = Ledger()

    ledger.record(uuid: first, roomToken: "t1", state: .ringing, source: .push, at: 10)

    XCTAssertEqual(
      ledger.entry(for: first),
      Ledger.Entry(uuid: first.uuidString, t: "t1", state: .ringing, source: .push, ts: 10))
    XCTAssertFalse(ledger.isResolved(first))
  }

  func testEveryStateButRingingResolvesTheCall() {
    for state in [Ledger.State.answered, .ended, .declined, .missed] {
      var ledger = Ledger()
      ledger.record(uuid: first, roomToken: "t1", state: state, source: .sync, at: 1)

      XCTAssertTrue(ledger.isResolved(first), state.rawValue)
      XCTAssertEqual(ledger.resolved, [first], state.rawValue)
    }
  }

  func testALaterStateReplacesTheEntryAndKeepsItsFirstSource() {
    var ledger = Ledger()
    ledger.record(uuid: first, roomToken: "t1", state: .ringing, source: .push, at: 1)

    ledger.record(uuid: first, roomToken: "", state: .declined, source: .sync, at: 2)

    XCTAssertEqual(ledger.calls.count, 1)
    XCTAssertEqual(
      ledger.entry(for: first),
      Ledger.Entry(uuid: first.uuidString, t: "t1", state: .declined, source: .push, ts: 2))
  }

  func testOnlyTheNewestSixtyFourCallsAreKept() {
    var ledger = Ledger()

    for index in 0..<70 {
      ledger.record(
        uuid: CallIdentity.uuid(roomId: "!a:zuno.im", callId: "c\(index)"), roomToken: "t",
        state: .ended, source: .sync, at: Int64(index))
    }

    XCTAssertEqual(ledger.calls.count, 64)
    XCTAssertNil(ledger.entry(for: CallIdentity.uuid(roomId: "!a:zuno.im", callId: "c5")))
    XCTAssertNotNil(ledger.entry(for: CallIdentity.uuid(roomId: "!a:zuno.im", callId: "c6")))
  }

  func testTheFileFormatRoundTripsWithItsContractKeys() throws {
    var ledger = Ledger()
    ledger.record(uuid: second, roomToken: "t2", state: .missed, source: .push, at: 99)

    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: ledger.encoded()) as? [String: Any])
    let call = try XCTUnwrap((json["calls"] as? [[String: Any]])?.first)

    XCTAssertEqual(json["v"] as? Int, 1)
    XCTAssertEqual(call["uuid"] as? String, second.uuidString)
    XCTAssertEqual(call["t"] as? String, "t2")
    XCTAssertEqual(call["state"] as? String, "missed")
    XCTAssertEqual(call["source"] as? String, "push")
    XCTAssertEqual(call["ts"] as? Int, 99)
    XCTAssertEqual(Ledger.decoded(ledger.encoded()), ledger)
  }

  func testAnotherVersionOrBrokenJsonReadsAsNoLedger() {
    XCTAssertNil(Ledger.decoded(Data(#"{"v":2,"calls":[]}"#.utf8)))
    XCTAssertNil(Ledger.decoded(Data("nope".utf8)))
    XCTAssertNil(
      Ledger.decoded(
        Data(
          #"{"v":1,"calls":[{"uuid":"x","t":"","state":"exploded","source":"push","ts":1}]}"#.utf8))
    )
  }
}

final class ServerClockTests: XCTestCase {
  func testServerTimeIsDeviceTimePlusTheOffset() {
    XCTAssertEqual(ServerClock(offsetMs: 1_500).now(deviceMs: 10_000), 11_500)
  }

  func testAnAuthenticatedSendTimeIsAFloor() {
    XCTAssertEqual(ServerClock(offsetMs: -5_000).now(deviceMs: 10_000, atLeast: 9_000), 9_000)
  }

  func testWithAKnownOffsetARingIsStaleTheMomentItsExpiryPasses() {
    let clock = ServerClock(offsetMs: 0)

    XCTAssertFalse(clock.isStale(expirySeconds: 100, deviceMs: 100_000))
    XCTAssertTrue(clock.isStale(expirySeconds: 100, deviceMs: 100_001))
  }

  func testWithoutAnOffsetTheDeviceClockGetsSixtySeconds() {
    let clock = ServerClock(offsetMs: nil)

    XCTAssertFalse(clock.isStale(expirySeconds: 100, deviceMs: 160_000))
    XCTAssertTrue(clock.isStale(expirySeconds: 100, deviceMs: 160_001))
  }

  func testTheRingLastsUntilFiveSecondsPastExpiryWithinItsCap() {
    let clock = ServerClock(offsetMs: 0)

    XCTAssertEqual(clock.ringSeconds(expirySeconds: 1_045, deviceMs: 1_001_000, cap: 55), 49)
    XCTAssertEqual(clock.ringSeconds(expirySeconds: 1_100, deviceMs: 1_000_000, cap: 55), 55)
    XCTAssertEqual(clock.ringSeconds(expirySeconds: 1_000, deviceMs: 1_000_000, cap: 55), 5)
  }

  func testAnObservedServerTimeSetsTheOffset() {
    var clock = ServerClock(offsetMs: nil)

    clock.observe(serverMs: 5_000, deviceMs: 4_000)

    XCTAssertEqual(clock.offsetMs, 1_000)
  }
}
