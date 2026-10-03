import XCTest

@testable import Runner

final class RingDecisionTests: XCTestCase {
  private let header = VoipBlobHeader(kid: 7, expiry: 1_790_000_045)
  private let ring = VoipRing(
    room: "!abc:zuno.im", call: "c1", caller: "@alice:zuno.im", cname: "Alice", rname: "",
    kind: .video, ts: 1_790_000_000_000, rts: 1_789_999_999_000)
  private let identity = CallIdentity.uuid(roomId: "!abc:zuno.im", callId: "c1")
  private let placeholder = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  private let other = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  private let delegates: [Bool?] = [nil, true]

  private func decide(
    _ blob: VoipBlobOpen? = nil, mustReport: Bool? = nil, locked: Bool = false,
    session: RingSession = .signedIn(userId: "@me:zuno.im"), now: Int64 = 1_790_000_001_000,
    offset: Int64? = 0, calls: CallsSnapshot = CallsSnapshot(), unknownKid: Int = 0,
    level: PreviewLevel = .full, room: RoomTitleFile? = nil
  ) -> RingOutcome {
    RingDecision.decide(
      RingInput(
        blob: blob ?? .opened(header, ring), mustReport: mustReport, beforeFirstUnlock: locked,
        session: session, nowMs: now, clock: ServerClock(offsetMs: offset), calls: calls,
        unknownKidRecent: unknownKid, level: level, placeholder: placeholder,
        room: { roomId in room?.room == roomId ? room : nil }))
  }

  private var freshCall: RingCall {
    RingCall(
      uuid: identity, roomId: "!abc:zuno.im", callId: "c1", callerId: "@alice:zuno.im",
      name: "Alice", video: true, ringSeconds: 49)
  }

  func testAFreshRingReportsUnderItsUuidWithItsNameAndVideoAndPrewarms() {
    for mustReport in [nil, true, false] {
      let outcome = decide(mustReport: mustReport)

      XCTAssertEqual(outcome.action, .ring(freshCall), "\(String(describing: mustReport))")
      XCTAssertTrue(outcome.prewarm)
      XCTAssertEqual(outcome.log, "ring")
    }
  }

  func testTheSameCallAlreadyTrackedIsReportedAgainThenUpdated() {
    let calls = CallsSnapshot(ringing: other, identities: [identity: other])
    for mustReport in delegates {
      XCTAssertEqual(
        decide(mustReport: mustReport, calls: calls).action,
        .update(uuid: other, name: "Alice", video: true, reportAgain: true))
    }
    XCTAssertEqual(
      decide(mustReport: false, calls: calls).action,
      .update(uuid: other, name: "Alice", video: true, reportAgain: false))
  }

  func testAnotherRingingCallTakesASilentDuplicateReport() {
    let calls = CallsSnapshot(ringing: other)
    for mustReport in delegates {
      XCTAssertEqual(decide(mustReport: mustReport, calls: calls).action, .duplicate(other))
    }
    XCTAssertEqual(decide(mustReport: false, calls: calls).action, .complete)
  }

  func testAnActiveCallTakesASilentDuplicateReport() {
    let calls = CallsSnapshot(active: other)
    for mustReport in delegates {
      XCTAssertEqual(decide(mustReport: mustReport, calls: calls).action, .duplicate(other))
    }
    XCTAssertEqual(decide(mustReport: false, calls: calls).action, .complete)
  }

  func testAStaleRingIsReportedThenEndedUnanswered() {
    for mustReport in delegates {
      XCTAssertEqual(
        decide(mustReport: mustReport, now: 1_790_000_046_000).action,
        .reportThenEnd(uuid: placeholder, reason: .unanswered))
    }
    XCTAssertEqual(decide(mustReport: false, now: 1_790_000_046_000).action, .complete)
  }

  func testWithoutAServerOffsetTheDeviceClockGetsSixtySeconds() {
    XCTAssertEqual(decide(now: 1_790_000_100_000, offset: nil).action.isRing, true)
    XCTAssertEqual(
      decide(now: 1_790_000_106_000, offset: nil).action,
      .reportThenEnd(uuid: placeholder, reason: .unanswered))
  }

  func testAResolvedCallIsReportedThenEnded() {
    let calls = CallsSnapshot(resolved: [identity])
    for mustReport in delegates {
      XCTAssertEqual(
        decide(mustReport: mustReport, calls: calls).action,
        .reportThenEnd(uuid: placeholder, reason: .unanswered))
    }
    XCTAssertEqual(decide(mustReport: false, calls: calls).action, .complete)
  }

  func testEndingWhileAnotherCallIsTrackedReportsUnderThatCallInstead() {
    XCTAssertEqual(
      decide(calls: CallsSnapshot(active: other, resolved: [identity])).action,
      .duplicate(other))
  }

  func testMyOwnCallIsReportedThenEnded() {
    let outcome = decide(session: .signedIn(userId: "@alice:zuno.im"))

    XCTAssertEqual(outcome.action, .reportThenEnd(uuid: placeholder, reason: .remoteEnded))
    XCTAssertEqual(outcome.log, "own_call")
    XCTAssertEqual(
      decide(mustReport: false, session: .signedIn(userId: "@alice:zuno.im")).action, .complete)
  }

  func testSignedOutOrNoSessionReportsThenEndsAndStopsVoip() {
    for session in [RingSession.signedOut, .noSession] {
      for mustReport in delegates {
        let outcome = decide(mustReport: mustReport, session: session)
        XCTAssertEqual(outcome.action, .reportThenEnd(uuid: placeholder, reason: .remoteEnded))
        XCTAssertTrue(outcome.disablePushTypes)
      }
      let skipped = decide(mustReport: false, session: session)
      XCTAssertEqual(skipped.action, .complete)
      XCTAssertTrue(skipped.disablePushTypes)
    }
  }

  func testAnUnknownKidRingsGenericallyAndAsksToRegisterAgainWhateverMustReportSays() {
    for mustReport in [nil, true, false] {
      let outcome = decide(.unknownKid(header), mustReport: mustReport)

      XCTAssertEqual(
        outcome.action,
        .generic(GenericRing(uuid: placeholder, ringSeconds: 45, beforeFirstUnlock: false)))
      XCTAssertTrue(outcome.reregister)
      XCTAssertTrue(outcome.prewarm)
    }
  }

  func testAnUnknownVersionRingsGenericallyToo() {
    XCTAssertEqual(
      decide(.unknownVersion).action,
      .generic(GenericRing(uuid: placeholder, ringSeconds: 45, beforeFirstUnlock: false)))
  }

  func testAThirdUnknownKidWithinTenMinutesIsReportedThenEnded() {
    let outcome = decide(.unknownKid(header), unknownKid: 2)

    XCTAssertEqual(outcome.action, .reportThenEnd(uuid: placeholder, reason: .failed))
    XCTAssertTrue(outcome.reregister)
  }

  func testAStaleUnknownKidIsReportedThenEnded() {
    XCTAssertEqual(
      decide(.unknownKid(header), now: 1_790_000_046_000).action,
      .reportThenEnd(uuid: placeholder, reason: .unanswered))
  }

  func testAnUnknownKidWhileAnotherCallRingsIsASilentDuplicate() {
    XCTAssertEqual(
      decide(.unknownKid(header), calls: CallsSnapshot(ringing: other)).action, .duplicate(other))
  }

  func testAForgedRingIsReportedThenEndedAsFailed() {
    for mustReport in delegates {
      let outcome = decide(.forged(header), mustReport: mustReport)
      XCTAssertEqual(outcome.action, .reportThenEnd(uuid: placeholder, reason: .failed))
      XCTAssertEqual(outcome.log, "forged")
    }
    XCTAssertEqual(decide(.forged(header), mustReport: false).action, .complete)
  }

  func testAPushWithoutAReadableBlobIsForged() {
    let outcome = decide(.forged(nil))

    XCTAssertEqual(outcome.action, .reportThenEnd(uuid: placeholder, reason: .failed))
    XCTAssertEqual(outcome.log, "forged")
  }

  func testACanaryIsReportedThenEnded() {
    let canary = VoipRing(
      room: "!abc:zuno.im", call: "probe", caller: "@ops:zuno.im", cname: "", rname: "",
      kind: .canary, ts: 1_790_000_000_000, rts: 1_790_000_000_000)

    let outcome = decide(.opened(header, canary))

    XCTAssertEqual(outcome.action, .reportThenEnd(uuid: placeholder, reason: .remoteEnded))
    XCTAssertEqual(outcome.log, "canary")
  }

  func testBeforeFirstUnlockAFreshRingIsGenericWithoutAnEngine() {
    for mustReport in delegates {
      let outcome = decide(.unknownKid(header), mustReport: mustReport, locked: true)

      XCTAssertEqual(
        outcome.action,
        .generic(GenericRing(uuid: placeholder, ringSeconds: 45, beforeFirstUnlock: true)))
      XCTAssertFalse(outcome.prewarm)
    }
    XCTAssertEqual(decide(.unknownKid(header), mustReport: false, locked: true).action, .complete)
  }

  func testBeforeFirstUnlockTheDeviceClockGetsSixtySeconds() {
    XCTAssertTrue(
      decide(.unknownKid(header), locked: true, now: 1_790_000_105_000).action.isGeneric)
    XCTAssertEqual(
      decide(.unknownKid(header), locked: true, now: 1_790_000_105_001).action,
      .reportThenEnd(uuid: placeholder, reason: .unanswered))
  }

  func testBeforeFirstUnlockAnUnknownVersionRingsGenerically() {
    XCTAssertEqual(
      decide(.unknownVersion, locked: true).action,
      .generic(GenericRing(uuid: placeholder, ringSeconds: 45, beforeFirstUnlock: true)))
  }

  func testBeforeFirstUnlockAPushWithoutABlobIsReportedThenEnded() {
    XCTAssertEqual(
      decide(.forged(nil), locked: true).action,
      .reportThenEnd(uuid: placeholder, reason: .failed))
  }

  func testAChatNamesItsPartnerAndARoomItsTitle() {
    let chat = RoomTitleFile(room: "!abc:zuno.im", title: "Alice B.", dm: true, partner: "Alice")
    let group = RoomTitleFile(room: "!abc:zuno.im", title: "Design team", dm: false, partner: "")

    XCTAssertEqual(decide(room: chat).action.ringName, "Alice")
    XCTAssertEqual(decide(room: group).action.ringName, "Design team")
  }

  func testWithoutATitleFileTheBlobNamesAreUsed() {
    let named = VoipRing(
      room: "!abc:zuno.im", call: "c1", caller: "@alice:zuno.im", cname: "Alice",
      rname: "Design team", kind: .voice, ts: 1_790_000_000_000, rts: 1_790_000_000_000)

    XCTAssertEqual(decide(.opened(header, named)).action.ringName, "Design team")
    XCTAssertEqual(decide().action.ringName, "Alice")
  }

  func testAtNothingEveryRingIsAZunoCall() {
    let chat = RoomTitleFile(room: "!abc:zuno.im", title: "Alice", dm: true, partner: "Alice")

    XCTAssertEqual(decide(level: .none, room: chat).action.ringName, "Zuno call")
  }

  func testAtNothingARingFromAnUnknownRoomNeverShowsTheSealedNames() {
    let named = VoipRing(
      room: "!abc:zuno.im", call: "c1", caller: "@alice:zuno.im", cname: "Alice",
      rname: "Design team", kind: .voice, ts: 1_790_000_000_000, rts: 1_790_000_000_000)

    XCTAssertEqual(decide(.opened(header, named), level: .none).action.ringName, "Zuno call")
  }

  func testTheDisplaySanitizerMatchesEveryContractNameCase() throws {
    let fixture = try ContractFixture.load("names_v1.json")
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    XCTAssertFalse(cases.isEmpty)
    for entry in cases {
      XCTAssertEqual(
        CallerName.sanitize(try XCTUnwrap(entry["input"])), entry["output"],
        entry["name"] ?? "?")
    }
  }

  func testTheStripPredicateIsTheSanitizersOwn() {
    let stripped: [Unicode.Scalar] = [
      "\u{0000}", "\u{001F}", "\u{007F}", "\u{0085}", "\u{009F}", "\u{061C}", "\u{200E}",
      "\u{200F}", "\u{202A}", "\u{202E}", "\u{2066}", "\u{2069}",
    ]
    let kept: [Unicode.Scalar] = [
      "a", "\u{00A0}", "\u{200D}", "\u{FEFF}", "\u{2065}", "\u{206A}", "\u{2070}",
    ]

    for scalar in stripped {
      XCTAssertTrue(CallerName.isStripped(scalar), String(scalar.value, radix: 16))
    }
    for scalar in kept {
      XCTAssertFalse(CallerName.isStripped(scalar), String(scalar.value, radix: 16))
    }
  }

  func testANameThatCleansToNothingOrOnlySpacesIsAZunoCall() {
    XCTAssertEqual(CallerName.shown("\u{200F}", level: .full), "Zuno call")
    XCTAssertEqual(CallerName.shown(" \u{0007} ", level: .full), "Zuno call")
    XCTAssertEqual(CallerName.shown("Ann\u{007F}a", level: .name), "Anna")
  }

  func testSealedNamesAndTitleFilesAreCleanedBeforeTheyRing() {
    let sealed = VoipRing(
      room: "!abc:zuno.im", call: "c1", caller: "@alice:zuno.im", cname: "\u{202E}Alice\u{200F}",
      rname: "", kind: .voice, ts: 1_790_000_000_000, rts: 1_790_000_000_000)
    let room = RoomTitleFile(
      room: "!abc:zuno.im", title: "\u{2067}Design\u{0000} team", dm: false, partner: "")

    XCTAssertEqual(decide(.opened(header, sealed)).action.ringName, "Alice")
    XCTAssertEqual(decide(room: room).action.ringName, "Design team")
  }
}

extension RingAction {
  var isRing: Bool {
    if case .ring = self { return true }
    return false
  }

  var isGeneric: Bool {
    if case .generic = self { return true }
    return false
  }

  var ringName: String? {
    if case .ring(let call) = self { return call.name }
    return nil
  }
}
