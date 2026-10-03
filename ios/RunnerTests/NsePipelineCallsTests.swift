import XCTest

@testable import Runner

final class NsePipelineCallsTests: XCTestCase {
  private let roomToken = "t\(NseTestData.roomId)"
  private let uuid = CallIdentity.uuid(roomId: NseTestData.roomId, callId: "c2")

  private func harness(meta: [String: Any] = NseTestData.meta()) -> NseHarness {
    let harness = NseHarness()
    harness.files.put(NotifyFile.meta, meta)
    harness.files.put(NotifyFile.room(roomToken), NseTestData.room(title: "Alice", dm: true))
    return harness
  }

  private func invite(video: Bool = true) -> NseHttpResult {
    NseTestData.ok(
      NseTestData.event(
        content: [
          "msgtype": "im.zuno.call_invite", "body": "Incoming call", "call_id": "c2",
          "kind": video ? "video" : "voice",
        ], ageMs: 2000))
  }

  private func ledger(_ uuid: UUID) -> Data {
    var ledger = Ledger()
    ledger.record(uuid: uuid, roomToken: "t", state: .ringing, source: .push, at: 1)
    return ledger.encoded()
  }

  func testAnInviteTheLedgerAlreadyHasIsAQuietCallLine() async {
    let harness = harness()
    _ = harness.files.write(NotifyFile.ledger, ledger(uuid))
    harness.transport.reply("nse/fetch", invite())

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .callHandled)
    XCTAssertEqual(result.delivery.body, "Video call")
    XCTAssertEqual(result.delivery.interruption, .passive)
    XCTAssertEqual(harness.transport.requests.map(\.path), ["nse/fetch"])
  }

  func testARingLandingDuringTheWaitKeepsTheLineQuiet() async {
    let harness = harness()
    let files = harness.files
    let entry = ledger(uuid)
    harness.clock.onWait { now in
      if now >= NseTestData.now + 1000 { _ = files.write(NotifyFile.ledger, entry) }
    }
    harness.transport.reply("nse/fetch", invite())

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .callHandled)
    XCTAssertEqual(harness.clock.waits.count, 4)
    XCTAssertEqual(
      harness.clock.waits.first, "250:im.zuno.chat.ring.changed,im.zuno.chat.calls.changed")
  }

  func testAFailedRingBecomesATimeSensitiveFallback() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite())
    harness.transport.reply("ring/status", NseFakeTransport.module(200, ["status": "no_token"]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .fallbackRing)
    XCTAssertEqual(result.delivery.title, "Alice")
    XCTAssertEqual(result.delivery.body, "Incoming video call")
    XCTAssertEqual(result.delivery.interruption, .timeSensitive)
    XCTAssertEqual(result.delivery.sound, .ring)
    XCTAssertEqual(result.delivery.userInfo["rg"], "rg\(uuid.uuidString)")
    XCTAssertEqual(harness.best.all.map(\.interruption), [.active, .passive, .timeSensitive])
    XCTAssertEqual(harness.transport.requests.last?.body?["call_id"], .string("c2"))
  }

  func testTheFallbackFollowsTheRingtoneSwitch() async {
    let harness = harness(meta: NseTestData.meta(["ringtone": false]))
    harness.transport.reply("nse/fetch", invite(video: false))
    harness.transport.reply("ring/status", NseFakeTransport.module(200, ["status": "failed"]))

    let result = await harness.run()

    XCTAssertEqual(result.delivery.body, "Incoming voice call")
    XCTAssertEqual(result.delivery.sound, .silentRing)
  }

  func testASuppressedOrPendingRingStaysQuiet() async {
    let statuses: [[String: Any]] = [
      ["status": "suppressed", "rule": "not_allowed"],
      ["status": "suppressed", "rule": "a_rule_from_a_newer_module"],
      ["status": "pending"],
    ]
    for status in statuses {
      let harness = harness()
      harness.transport.reply("nse/fetch", invite())
      harness.transport.reply("ring/status", NseFakeTransport.module(200, status))
      let result = await harness.run()
      XCTAssertEqual(result.outcome, .callHandled)
      XCTAssertEqual(result.delivery.interruption, .passive)
    }
  }

  func testAFailingVoipRouteRingsTheFallbackLikeAFailure() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite())
    harness.transport.reply(
      "ring/status",
      NseFakeTransport.module(200, ["status": "suppressed", "rule": "voip_failing"]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .fallbackRing)
    XCTAssertEqual(result.delivery.interruption, .timeSensitive)
  }

  func testAnUnknownStatusRingsTheFallback() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite())
    harness.transport.reply(
      "ring/status", NseFakeTransport.module(200, ["status": "queued", "server_ts": 1]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .fallbackRing)
  }

  func testAnUnreachableStatusEndsInTheFallback() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite())
    harness.transport.reply("ring/status", .response(status: 502, headers: [:], body: Data()))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .fallbackRing)
  }

  func testASentRingThatNeverLandsFallsBackEightSecondsAfterSending() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite())
    harness.transport.reply(
      "ring/status",
      NseFakeTransport.module(
        200,
        ["status": "sent", "sent_ts": NseTestData.now + 7000, "server_ts": NseTestData.now + 8000]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .fallbackRing)
    XCTAssertEqual(harness.clock.nowMs(), NseTestData.now + 15_000)
  }

  func testASentRingWithoutItsTimeFallsBackEightSecondsAfterTheAnswer() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite())
    harness.transport.reply(
      "ring/status",
      NseFakeTransport.module(200, ["status": "sent", "server_ts": NseTestData.now + 8000]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .fallbackRing)
    XCTAssertEqual(harness.clock.nowMs(), NseTestData.now + 16_000)
  }

  func testTheStatusWaitNeverPassesTheBudget() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", invite(), after: 7000)
    harness.transport.reply("ring/status", NseFakeTransport.module(200, ["status": "pending"]))

    _ = await harness.run()

    XCTAssertEqual(harness.transport.requests.last?.body?["wait_ms"]?.int64, 8000)
  }

  func testAMissedCallShowsOnceAndTellsTheAppToStopRinging() async {
    let content: [String: Any] = [
      "msgtype": "im.zuno.call_summary", "body": "Missed Voice call", "call_id": "c2",
      "kind": "voice", "status": "missed", "duration_ms": 0,
    ]
    let harness = harness()
    harness.transport.reply("nse/fetch", NseTestData.ok(NseTestData.event(content: content)))
    harness.transport.reply(
      "nse/fetch", NseTestData.ok(NseTestData.event(content: content, eventId: "$ev2")))

    let first = await harness.run()
    let second = await harness.run(
      NsePush(id: "p2", roomId: NseTestData.roomId, eventId: "$ev2", receivedMs: NseTestData.now))

    XCTAssertEqual(first.outcome, .shown)
    XCTAssertEqual(first.delivery.body, "Missed Voice call")
    XCTAssertEqual(second.outcome, .hidden)
    XCTAssertEqual(
      SeenSets.marks(harness.files.read(NotifyFile.marks)).map(\.status), ["missed", "missed"])
    XCTAssertEqual(harness.signals.posted.first, "im.zuno.chat.calls.changed")
  }

  func testADeclinedCallIsHiddenButStillEndsTheRing() async {
    let harness = harness()
    harness.transport.reply(
      "nse/fetch",
      NseTestData.ok(
        NseTestData.event(content: [
          "msgtype": "im.zuno.call_summary", "body": "Voice call declined", "call_id": "c2",
          "kind": "voice", "status": "declined",
        ])))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .hidden)
    XCTAssertEqual(SeenSets.marks(harness.files.read(NotifyFile.marks)).first?.call, "c2")
  }

  func testAnInvitationShowsOnceAndIsHandedToTheApp() async {
    let harness = harness()
    for eventId in [NseTestData.eventId, "$ev2"] {
      harness.transport.reply(
        "nse/fetch",
        NseTestData.ok(
          NseTestData.event(
            type: "m.room.member", content: ["membership": "invite"], eventId: eventId,
            stateKey: NseTestData.me)))
    }

    let first = await harness.run()
    let second = await harness.run(
      NsePush(id: "p2", roomId: NseTestData.roomId, eventId: "$ev2", receivedMs: NseTestData.now))

    XCTAssertEqual(first.outcome, .shown)
    XCTAssertEqual(first.delivery.title, "Alice")
    XCTAssertEqual(first.delivery.body, "Invited you to chat")
    XCTAssertEqual(first.delivery.userInfo["k"], "inv")
    XCTAssertEqual(second.outcome, .duplicate)
    XCTAssertEqual(SeenSets.marks(harness.files.read(NotifyFile.marks)).map(\.kind), ["invite"])
  }

  func testAnInvitationTheAppAnnouncedIsNotAnnouncedAgain() async {
    let harness = harness()
    harness.files.put(NotifyFile.shownApp, ["v": 1, "e": ["einvite:\(NseTestData.roomId)"]])
    harness.transport.reply(
      "nse/fetch",
      NseTestData.ok(
        NseTestData.event(
          type: "m.room.member", content: ["membership": "invite"], stateKey: NseTestData.me)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .duplicate)
    XCTAssertEqual(result.delivery.interruption, .passive)
  }

  func testAVerificationRequestAsksPlainly() async {
    let harness = harness()
    harness.transport.reply(
      "nse/fetch",
      NseTestData.ok(
        NseTestData.event(content: [
          "msgtype": "m.key.verification.request", "body": "x", "to": NseTestData.me,
          "from_device": "D", "methods": ["m.sas.v1"],
        ])))

    let result = await harness.run()

    XCTAssertEqual(result.delivery.title, "Alice")
    XCTAssertEqual(result.delivery.body, "Wants to verify you")
    XCTAssertEqual(result.delivery.userInfo["k"], "sys")
  }
}
