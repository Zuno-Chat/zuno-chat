@preconcurrency import CallKit
import UIKit
import XCTest

@testable import Runner

@MainActor
final class CallKitCenterSyncTests: XCTestCase {
  private func reportDartRing(_ harness: CallKitHarness, completion: @escaping (String) -> Void) {
    harness.center.reportIncoming(
      roomId: "!r:zuno.im", callId: "c1", callerId: "", name: "Alice", isVideo: false,
      completion: completion)
  }

  func testADartRingReportsOnceAndShowsWhenCallKitAccepts() {
    let harness = CallKitHarness()
    var outcome: String?

    harness.center.reportIncoming(
      roomId: "!r:zuno.im", callId: "c1", callerId: "@alice:zuno.im", name: "Alice",
      isVideo: true
    ) { outcome = $0 }

    XCTAssertEqual(harness.provider.reports.map(\.name), ["Alice"])
    XCTAssertEqual(harness.provider.reports.first?.handle, "t-!r:zuno.im")
    XCTAssertNil(outcome)
    harness.provider.complete()
    XCTAssertEqual(outcome, "shown")
    XCTAssertEqual(
      harness.ledger,
      [
        CallLedgerChange(
          identity: CallIdentity.uuid(roomId: "!r:zuno.im", callId: "c1"), roomId: "!r:zuno.im",
          state: .ringing, source: .sync)
      ])
  }

  func testADartRingForACallAlreadyTrackedIsShownWithoutASecondReport() {
    let harness = CallKitHarness()
    reportDartRing(harness) { _ in }
    var outcome: String?

    reportDartRing(harness) { outcome = $0 }

    XCTAssertEqual(outcome, "shown")
    XCTAssertEqual(harness.provider.reports.count, 1)
  }

  func testADartRingForACallTheLedgerResolvedIsFilteredWithoutAReport() {
    let harness = CallKitHarness(
      resolved: [CallIdentity.uuid(roomId: "!r:zuno.im", callId: "c1")])
    var outcome: String?

    reportDartRing(harness) { outcome = $0 }

    XCTAssertEqual(outcome, "filtered")
    XCTAssertTrue(harness.provider.reports.isEmpty)
  }

  func testAnEndedCallIsTombstonedForLaterDartRings() {
    let harness = CallKitHarness()
    reportDartRing(harness) { _ in }
    harness.provider.complete()
    harness.center.endIncoming(roomId: "!r:zuno.im", callId: "c1", reason: .remoteEnded)
    var outcome: String?

    reportDartRing(harness) { outcome = $0 }

    XCTAssertEqual(outcome, "filtered")
    XCTAssertEqual(harness.ledger.last?.state, .ended)
  }

  func testWithoutCallKitADartRingIsUnavailable() {
    let harness = CallKitHarness(available: false)
    var outcome: String?

    reportDartRing(harness) { outcome = $0 }

    XCTAssertEqual(outcome, "unavailable")
  }

  func testAtNothingADartRingIsAZunoCall() {
    let harness = CallKitHarness(level: .none)

    reportDartRing(harness) { _ in }

    XCTAssertEqual(harness.provider.reports.first?.name, "Zuno call")
  }

  func testAnAnswerToADartRingIsFulfilledAtOnceAndHandedToDart() {
    let harness = CallKitHarness()
    harness.attachDart()
    harness.center.reportIncoming(
      roomId: "!r:zuno.im", callId: "c1", callerId: "@alice:zuno.im", name: "Alice",
      isVideo: false
    ) { _ in }
    harness.provider.complete()
    let action = FakeAnswerAction()

    harness.center.answer(CallIdentity.uuid(roomId: "!r:zuno.im", callId: "c1"), action: action)

    XCTAssertTrue(action.fulfilled)
    XCTAssertEqual(harness.sink.methods, ["answerCall"])
  }

  func testAnOutgoingCallUsesTheUuidOfItsRoomAndCall() {
    let harness = CallKitHarness()

    _ = harness.center.begin(roomId: "!r:zuno.im", callId: "out", title: "Room", isVideo: false)

    let outgoing = CallIdentity.uuid(roomId: "!r:zuno.im", callId: "out")
    XCTAssertEqual(harness.center.snapshot().identities[outgoing], outgoing)
  }

}

@MainActor
final class CallKitCenterPushTests: XCTestCase {
  private let uuid = CallIdentity.uuid(roomId: "!r:zuno.im", callId: "c1")

  private func genericRing(_ uuid: UUID, beforeFirstUnlock: Bool) -> RingAction {
    .generic(GenericRing(uuid: uuid, ringSeconds: 45, beforeFirstUnlock: beforeFirstUnlock))
  }

  private func waitUntil(_ settled: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(120)
    while !settled(), Date() < deadline {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func testAPushedRingIsReportedBeforeAnythingElseAndCompletesFromTheReport() {
    let harness = CallKitHarness()
    var report: PushReport?

    harness.center.reportPush(harness.pushRing(video: true)) { report = $0 }

    XCTAssertEqual(harness.provider.reports.map(\.uuid), [uuid])
    XCTAssertEqual(harness.provider.reports.first?.video, true)
    XCTAssertNil(report)
    harness.provider.complete()
    XCTAssertEqual(report, .shown(uuid))
    XCTAssertEqual(harness.ledger.map(\.state), [.ringing])
    XCTAssertEqual(harness.ledger.first?.source, .push)
  }

  func testAPushedRingTellsAnAttachedDartThatItRings() throws {
    let harness = CallKitHarness()
    harness.attachDart()

    harness.center.reportPush(harness.pushRing(video: true)) { _ in }
    harness.provider.complete()

    let (method, arguments) = try XCTUnwrap(harness.sink.events.first)
    XCTAssertEqual(method, "ringing")
    XCTAssertEqual(arguments["roomId"] as? String, "!r:zuno.im")
    XCTAssertEqual(arguments["callId"] as? String, "c1")
    XCTAssertEqual(arguments["uuid"] as? String, uuid.uuidString)
    XCTAssertEqual(arguments["video"] as? Bool, true)
    XCTAssertEqual(arguments["source"] as? String, "push")
  }

  func testAPushedRingBeforeDartAttachesIsReplayedOnce() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()

    let events = harness.center.takeEvents()

    XCTAssertEqual(events.compactMap { $0["method"] as? String }, ["ringing"])
    XCTAssertTrue(harness.sink.events.isEmpty)
  }

  func testAFilteredPushedRingStillCompletesAndIsRecordedMissed() {
    let harness = CallKitHarness()
    var report: PushReport?

    harness.center.reportPush(harness.pushRing()) { report = $0 }
    harness.provider.complete(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))

    XCTAssertEqual(report, .notShown)
    XCTAssertEqual(harness.ledger.map(\.state), [.missed])
  }

  func testCompletingWithoutAReportNeedsNoCallKit() {
    let harness = CallKitHarness()
    var report: PushReport?

    harness.center.reportPush(.complete) { report = $0 }

    XCTAssertEqual(report, .completed)
    XCTAssertTrue(harness.provider.reports.isEmpty)
  }

  func testReportThenEndShowsAPlaceholderAndEndsItWithTheReason() {
    let harness = CallKitHarness()
    let placeholder = UUID()
    var report: PushReport?

    harness.center.reportPush(.reportThenEnd(uuid: placeholder, reason: .unanswered)) {
      report = $0
    }

    XCTAssertEqual(harness.provider.reports.map(\.name), ["Zuno call"])
    XCTAssertEqual(harness.provider.reports.first?.handle, "zuno")
    harness.provider.complete()
    XCTAssertEqual(report, .completed)
    XCTAssertEqual(harness.provider.ended.map(\.0), [placeholder])
    XCTAssertEqual(harness.provider.ended.first?.1, .unanswered)
  }

  func testADuplicateReportUnderARingingCallStaysSilent() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()
    var report: PushReport?

    harness.center.reportPush(.duplicate(uuid)) { report = $0 }
    harness.provider.complete(CXErrorCodeIncomingCallError(.callUUIDAlreadyExists))

    XCTAssertEqual(harness.provider.reports.map(\.uuid), [uuid, uuid])
    XCTAssertEqual(report, .completed)
    XCTAssertTrue(harness.provider.ended.isEmpty)
  }

  func testAnUpdateRenamesAGenericRingAndAddsVideoButKeepsADartName() {
    let harness = CallKitHarness()
    harness.center.reportIncoming(
      roomId: "!r:zuno.im", callId: "c1", callerId: "", name: "Room name", isVideo: false
    ) { _ in }
    harness.provider.complete()

    harness.center.reportPush(
      .update(uuid: uuid, name: "Blob name", video: true, reportAgain: true)
    ) { _ in }
    harness.provider.complete(CXErrorCodeIncomingCallError(.callUUIDAlreadyExists))

    XCTAssertEqual(harness.provider.reports.count, 2)
    XCTAssertEqual(harness.provider.updates.last?.name, "Room name")
    XCTAssertEqual(harness.provider.updates.last?.video, true)
  }

  func testAReReportCallKitAcceptsAfterItsCallEndedIsEndedAtOnce() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()
    var report: PushReport?

    harness.center.reportPush(.update(uuid: uuid, name: "Alice", video: false, reportAgain: true)) {
      report = $0
    }
    harness.center.endIncoming(roomId: "!r:zuno.im", callId: "c1", reason: .remoteEnded)
    harness.provider.complete()

    XCTAssertEqual(report, .completed)
    XCTAssertEqual(harness.provider.ended.map(\.0), [uuid, uuid])
  }

  func testDartUpdatesTheNameAndVideoOfARingingCall() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing(name: "Zuno call")) { _ in }
    harness.provider.complete()

    harness.center.updateIncoming(roomId: "!r:zuno.im", callId: "c1", name: "Alice", isVideo: true)

    XCTAssertEqual(harness.provider.updates.last?.name, "Alice")
    XCTAssertEqual(harness.provider.updates.last?.video, true)
  }

  func testAGenericRingIsReplayedWithItsUuidButNoCall() throws {
    let harness = CallKitHarness()
    let generic = UUID()
    harness.center.reportPush(genericRing(generic, beforeFirstUnlock: false)) { _ in }
    harness.provider.complete()

    let arguments = try XCTUnwrap(harness.center.takeEvents().first?["arguments"] as? [String: Any])

    XCTAssertEqual(harness.provider.reports.first?.name, "Zuno call")
    XCTAssertEqual(arguments["uuid"] as? String, generic.uuidString)
    XCTAssertEqual(arguments["source"] as? String, "generic")
    XCTAssertNil(arguments["roomId"])
    XCTAssertNil(arguments["callId"])
    XCTAssertTrue(harness.ledger.isEmpty)
  }

  func testAnAnswerToAPushedRingIsHeldUntilTheCallConnects() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()
    let action = FakeAnswerAction()

    harness.center.answer(uuid, action: action)

    XCTAssertFalse(action.fulfilled)
    XCTAssertEqual(
      harness.center.takeEvents().compactMap { $0["method"] as? String }, ["answerCall"])
    harness.center.connected(roomId: "!r:zuno.im", callId: "c1")
    XCTAssertTrue(action.fulfilled)
    XCTAssertEqual(harness.ledger.map(\.state), [.ringing, .answered])
  }

  func testAHeldAnswerIsFulfilledTwoSecondsBeforeItWouldTimeOut() async throws {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()
    let action = FakeAnswerAction(timeout: 2.2)

    harness.center.answer(uuid, action: action)
    try await waitUntil { action.fulfilled || action.failed }

    XCTAssertTrue(action.fulfilled)
    XCTAssertFalse(action.failed)
  }

  func testAnAnswerToARingWithoutItsCallWaitsForTheBinding() throws {
    let harness = CallKitHarness()
    let generic = UUID()
    harness.center.reportPush(genericRing(generic, beforeFirstUnlock: false)) { _ in }
    harness.provider.complete()
    _ = harness.center.takeEvents()
    let action = FakeAnswerAction()

    harness.center.answer(generic, action: action)
    XCTAssertTrue(harness.sink.events.isEmpty)

    XCTAssertTrue(
      harness.center.bind(
        uuid: generic, roomId: "!r:zuno.im", callId: "c1", callerId: "@alice:zuno.im",
        name: "Alice", isVideo: true))

    let (method, arguments) = try XCTUnwrap(harness.sink.events.first)
    XCTAssertEqual(method, "answerCall")
    XCTAssertEqual(arguments["callId"] as? String, "c1")
    XCTAssertEqual(harness.provider.updates.last?.name, "Alice")
    XCTAssertEqual(harness.ledger.map(\.state), [.answered])
    harness.center.connected(roomId: "!r:zuno.im", callId: "c1")
    XCTAssertTrue(action.fulfilled)
  }

  func testAnAnswerThatNeverLearnsItsCallEndsAsFailed() async throws {
    let harness = CallKitHarness()
    let generic = UUID()
    harness.center.reportPush(genericRing(generic, beforeFirstUnlock: true)) { _ in }
    harness.provider.complete()
    let action = FakeAnswerAction(timeout: 2.2)

    harness.center.answer(generic, action: action)
    try await waitUntil { action.failed }

    XCTAssertTrue(action.failed)
    XCTAssertEqual(harness.provider.ended.map(\.1), [.failed])
    XCTAssertEqual(harness.expired, [.bfu])
  }

  func testOnceUnlockedARingIsGenericAndStillOfferedToDartAfterAnAnswer() throws {
    let harness = CallKitHarness()
    let ring = UUID()
    harness.center.reportPush(genericRing(ring, beforeFirstUnlock: true)) { _ in }
    harness.provider.complete()
    harness.center.answer(ring, action: FakeAnswerAction())

    harness.center.treatAsGeneric(uuid: ring)

    let replayed = harness.center.takeEvents()
      .filter { $0["method"] as? String == "ringing" }
      .compactMap { $0["arguments"] as? [String: Any] }
    XCTAssertEqual(replayed.map { $0["uuid"] as? String }, [ring.uuidString])
    XCTAssertEqual(replayed.first?["source"] as? String, "generic")
    XCTAssertNil(replayed.first?["roomId"])
  }

  func testAnAnswerAfterUnlockThatNeverLearnsItsCallIsNoBeforeFirstUnlockMiss() async throws {
    let harness = CallKitHarness()
    let ring = UUID()
    harness.center.reportPush(genericRing(ring, beforeFirstUnlock: true)) { _ in }
    harness.provider.complete()
    harness.center.treatAsGeneric(uuid: ring)
    let action = FakeAnswerAction(timeout: 2.2)

    harness.center.answer(ring, action: action)
    try await waitUntil { action.failed }

    XCTAssertTrue(action.failed)
    XCTAssertEqual(harness.expired, [.generic])
  }

  func testAnAnswerHeldBeforeItsRingIsBoundIsStillFulfilledInTime() async throws {
    let harness = CallKitHarness()
    let ring = UUID()
    harness.center.reportPush(genericRing(ring, beforeFirstUnlock: true)) { _ in }
    harness.provider.complete()
    let action = FakeAnswerAction(timeout: 2.2)
    harness.center.answer(ring, action: action)

    harness.center.bind(
      uuid: ring, roomId: "!r:zuno.im", callId: "c1", callerId: "@alice:zuno.im",
      name: "Alice", isVideo: false)
    try await waitUntil { action.fulfilled || action.failed }

    XCTAssertTrue(action.fulfilled)
    XCTAssertFalse(action.failed)
  }

  func testOnlyAnUnboundBeforeFirstUnlockRingTurnsGeneric() throws {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()

    harness.center.treatAsGeneric(uuid: uuid)

    let replayed = try XCTUnwrap(harness.center.takeEvents().first?["arguments"] as? [String: Any])
    XCTAssertEqual(replayed["source"] as? String, "push")
  }

  func testBindingToACallAlreadyOverEndsTheRing() {
    let resolved = CallIdentity.uuid(roomId: "!r:zuno.im", callId: "over")
    let harness = CallKitHarness(resolved: [resolved])
    let generic = UUID()
    harness.center.reportPush(genericRing(generic, beforeFirstUnlock: false)) { _ in }
    harness.provider.complete()

    XCTAssertFalse(
      harness.center.bind(
        uuid: generic, roomId: "!r:zuno.im", callId: "over", callerId: "", name: "", isVideo: false
      ))
    XCTAssertEqual(harness.provider.ended.map(\.0), [generic])
  }

  func testEndingAnUnboundRingLeavesBoundCallsAlone() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()

    harness.center.endUnbound(uuid: uuid)

    XCTAssertTrue(harness.provider.ended.isEmpty)
  }

  func testADeclineFromTheLockScreenIsHandedToDartAndRecorded() {
    let harness = CallKitHarness()
    harness.attachDart()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()

    harness.center.systemEnd(uuid, actionId: UUID())
    harness.center.declineSent(roomId: "!r:zuno.im", callId: "c1")

    XCTAssertEqual(harness.sink.methods, ["ringing", "declineCall"])
    XCTAssertEqual(harness.ledger.map(\.state), [.ringing, .declined])
  }

  func testTheSnapshotNamesRingingAndActiveCallsByIdentity() {
    let harness = CallKitHarness()
    let second = CallIdentity.uuid(roomId: "!r:zuno.im", callId: "c2")
    harness.center.reportPush(harness.pushRing("c1")) { _ in }
    harness.provider.complete()
    harness.center.reportPush(harness.pushRing("c2")) { _ in }
    harness.provider.complete()
    harness.center.answer(second, action: FakeAnswerAction())

    let snapshot = harness.center.snapshot()

    XCTAssertEqual(snapshot.ringing, uuid)
    XCTAssertEqual(snapshot.active, second)
    XCTAssertEqual(snapshot.identities[uuid], uuid)
  }

  func testDartGetsFortyFiveSecondsToTakeOverAPushedAnswerAndThirtyForASyncOne() {
    XCTAssertEqual(CallKitCenter.adoptLimit(.sync), 30)
    XCTAssertEqual(CallKitCenter.adoptLimit(.push), 45)
    XCTAssertEqual(CallKitCenter.adoptLimit(.generic), 45)
    XCTAssertEqual(CallKitCenter.adoptLimit(.bfu), 45)
  }

  func testEndingACallWhoseAnswerIsHeldFailsThatAnswer() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()
    let action = FakeAnswerAction()
    harness.center.answer(uuid, action: action)

    harness.center.end(roomId: "!r:zuno.im", callId: "c1", reason: .failed, byUser: false)

    XCTAssertTrue(action.failed)
    XCTAssertFalse(action.fulfilled)
    XCTAssertEqual(harness.provider.ended.map(\.1), [.failed])
  }

  func testSigningOutEndsEveryCall() {
    let harness = CallKitHarness()
    harness.center.reportPush(harness.pushRing()) { _ in }
    harness.provider.complete()

    harness.center.endAll(reason: .remoteEnded)

    XCTAssertEqual(harness.provider.ended.map(\.0), [uuid])
    XCTAssertNil(harness.center.snapshot().ringing)
  }
}

final class CallKitRefusalTests: XCTestCase {
  func testNoErrorMeansTheRingIsShown() {
    XCTAssertNil(CallKitCenter.refusal(nil))
  }

  func testACallCallKitAlreadyShowsCountsAsShown() {
    XCTAssertNil(CallKitCenter.refusal(CXErrorCodeIncomingCallError(.callUUIDAlreadyExists)))
  }

  func testAnUnknownOrUnentitledRefusalMeansCallKitIsUnavailable() {
    XCTAssertEqual(CallKitCenter.refusal(CXErrorCodeIncomingCallError(.unknown)), "unavailable")
    XCTAssertEqual(CallKitCenter.refusal(CXErrorCodeIncomingCallError(.unentitled)), "unavailable")
  }

  func testAnErrorOutsideTheIncomingCallDomainMeansCallKitIsUnavailable() {
    XCTAssertEqual(CallKitCenter.refusal(URLError(.timedOut)), "unavailable")
    XCTAssertEqual(
      CallKitCenter.refusal(NSError(domain: NSCocoaErrorDomain, code: 3)), "unavailable")
    XCTAssertEqual(CallKitCenter.refusal(CXError(.unentitled)), "unavailable")
    XCTAssertEqual(
      CallKitCenter.refusal(CXErrorCodeRequestTransactionError(.callUUIDAlreadyExists)),
      "unavailable")
  }

  func testEveryOtherRefusalMeansTheRingWasFiltered() {
    let codes: [CXErrorCodeIncomingCallError.Code] = [
      .filteredByDoNotDisturb, .filteredByBlockList, .filteredDuringRestrictedSharingMode,
      .callIsProtected, .filteredBySensitiveParticipants,
    ]
    for code in codes {
      XCTAssertEqual(
        CallKitCenter.refusal(CXErrorCodeIncomingCallError(code)), "filtered", "\(code.rawValue)")
    }
  }

  func testARefusalBridgedFromObjectiveCIsReadByItsCode() {
    let domain = CXErrorCodeIncomingCallError.errorDomain
    XCTAssertNil(CallKitCenter.refusal(NSError(domain: domain, code: 2)))
    XCTAssertEqual(CallKitCenter.refusal(NSError(domain: domain, code: 1)), "unavailable")
    XCTAssertEqual(CallKitCenter.refusal(NSError(domain: domain, code: 3)), "filtered")
  }
}

final class CallKitRingtoneTests: XCTestCase {
  func testTheRingtoneSettingWinsAndTheRingFlagCoversItBeforeFirstUnlock() {
    XCTAssertNil(CallKitCenter.ringtoneSound(stored: true, flag: false))
    XCTAssertEqual(CallKitCenter.ringtoneSound(stored: false, flag: true), "silent_ring.caf")
    XCTAssertEqual(CallKitCenter.ringtoneSound(stored: nil, flag: false), "silent_ring.caf")
    XCTAssertNil(CallKitCenter.ringtoneSound(stored: nil, flag: nil))
  }

  func testAStoredNumberReadsAsTheSetting() {
    XCTAssertNil(CallKitCenter.ringtoneSound(stored: NSNumber(value: true), flag: false))
    XCTAssertEqual(
      CallKitCenter.ringtoneSound(stored: NSNumber(value: false), flag: nil), "silent_ring.caf")
  }

  func testAStoredValueThatIsNotABoolLeavesItToTheRingFlag() {
    for stored: Any in ["false", Data()] {
      XCTAssertNil(CallKitCenter.ringtoneSound(stored: stored, flag: nil), "\(stored)")
      XCTAssertEqual(
        CallKitCenter.ringtoneSound(stored: stored, flag: false), "silent_ring.caf", "\(stored)")
    }
  }

  func testAnOffSettingReadBackFromUserDefaultsSelectsTheSilentRing() throws {
    let suite = "im.zuno.chat.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "flutter.settings.ringtone_enabled")
    XCTAssertEqual(
      CallKitCenter.ringtoneSound(
        stored: defaults.object(forKey: "flutter.settings.ringtone_enabled"), flag: true),
      "silent_ring.caf")
  }
}

final class CallKitSystemEndTests: XCTestCase {
  func testASystemEndInTheFirst25SecondsOfRingingIsADecline() {
    for ringing: TimeInterval in [0, 1, 24.9] {
      XCTAssertEqual(
        CallKitCenter.systemEndEvent(ringingFor: ringing, answerWithdrawn: false), "declineCall",
        "\(ringing) s")
    }
  }

  func testASystemEndAfter25SecondsOfRingingIsAMissedRing() {
    for ringing: TimeInterval in [25, 25.1, 55, 60] {
      XCTAssertEqual(
        CallKitCenter.systemEndEvent(ringingFor: ringing, answerWithdrawn: false), "ringEnded",
        "\(ringing) s")
    }
  }

  func testASystemEndOfAnAnswerTheAppNeverTookIsADecline() {
    XCTAssertEqual(
      CallKitCenter.systemEndEvent(ringingFor: nil, answerWithdrawn: true), "declineCall")
  }

  func testASystemEndOfAnOngoingCallIsAHangUp() {
    XCTAssertEqual(
      CallKitCenter.systemEndEvent(ringingFor: nil, answerWithdrawn: false), "hangUpCall")
  }
}

final class CallKitResourceTests: XCTestCase {
  func testTheAppBundleShipsTheSilentRing() throws {
    let name = try XCTUnwrap(CallKitCenter.ringtoneSound(stored: false, flag: nil))
    XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil))
  }

  func testTheAppBundleShipsTheCallKitIcon() {
    XCTAssertNotNil(UIImage(named: "CallKitIcon")?.pngData())
  }
}
