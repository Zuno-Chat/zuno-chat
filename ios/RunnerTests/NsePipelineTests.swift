import XCTest

@testable import Runner

final class NsePipelineTests: XCTestCase {
  private let roomToken = "t\(NseTestData.roomId)"
  private let eventToken = "e\(NseTestData.eventId)"

  private func harness(
    meta: [String: Any] = NseTestData.meta(), room: [String: Any]? = NseTestData.room(),
    delivered: [NseDelivered] = [], plaintexts: [String: String] = [:],
    keychain: NotifySecretsRead = .ready(NseTestData.keys)
  ) -> NseHarness {
    let harness = NseHarness(keychain: keychain, delivered: delivered, plaintexts: plaintexts)
    harness.files.put(NotifyFile.meta, meta)
    if let room { harness.files.put(NotifyFile.room(roomToken), room) }
    return harness
  }

  private func encrypted(_ index: UInt8, session: String = "s1", tag: UInt8 = 1) -> [String: Any] {
    NseTestData.event(
      type: "m.room.encrypted",
      content: [
        "algorithm": "m.megolm.v1.aes-sha2", "session_id": session, "sender_key": "k1",
        "ciphertext": NseTestData.ciphertext(index: index, tag: tag),
      ])
  }

  private func session(first: Int = 0, sender: String? = "@alice:zuno.im") -> [String: Any] {
    var session: [String: Any] = [
      "session_id": "s1", "sender_key": "k1", "first_index": first, "pickle": "p1",
    ]
    if let sender { session["sender"] = sender }
    return session
  }

  private func plaintext(_ body: String, room: String = NseTestData.roomId) -> String {
    #"{"type":"m.room.message","content":{"msgtype":"m.text","body":"\#(body)"},"room_id":"\#(room)"}"#
  }

  func testATestPushSaysNotificationsWorkAndLeavesAnAck() async {
    let harness = harness()

    let result = await harness.run(
      NsePush(id: "p", roomId: nil, eventId: "$zuno_test_1", receivedMs: NseTestData.now))

    XCTAssertEqual(result.outcome, .test)
    XCTAssertEqual(result.delivery.body, "Notifications work")
    XCTAssertEqual(SeenSets.marks(harness.files.read(NotifyFile.marks)).map(\.kind), ["test"])
    XCTAssertTrue(harness.transport.requests.isEmpty)
    XCTAssertEqual(harness.signals.logged, ["nse_test t=- ms=0 safe=0"])
  }

  func testATestPushBeforeFirstUnlockStillShowsButWritesNothing() async {
    let harness = harness(keychain: .locked)

    let result = await harness.run(
      NsePush(id: "p", roomId: nil, eventId: "$zuno_test_1", receivedMs: NseTestData.now))

    XCTAssertEqual(result.outcome, .test)
    XCTAssertNil(harness.files.read(NotifyFile.marks))
  }

  func testBeforeFirstUnlockTheOriginalContentShowsAndNothingIsWritten() async {
    let harness = harness(keychain: .locked)

    let result = await harness.run()

    XCTAssertEqual(result, NseResult(delivery: .passthrough, outcome: .bfu))
    XCTAssertNil(harness.files.read(NotifyFile.shownNse))
    XCTAssertTrue(harness.transport.requests.isEmpty)
  }

  func testWithoutKeysMetaOrIdsTheOriginalContentShows() async {
    let missingKeys = await harness(keychain: .unavailable).run()
    let missingMeta = await harness(meta: [:]).run()
    let missingIds = await harness().run(NseTestData.push(eventId: nil))

    XCTAssertEqual(missingKeys.outcome, .noMeta)
    XCTAssertEqual(missingMeta.outcome, .noMeta)
    XCTAssertEqual(missingIds.outcome, .malformed)
    XCTAssertTrue(missingIds.delivery.usesOriginal)
  }

  func testUntilTheAppTurnsTheExtensionOnTheStaticAlertShowsUntouched() async {
    let harness = harness(meta: [
      "v": 1, "user": NseTestData.me, "device": "D", "ringtone": true, "voip_current": true,
      "heartbeat_ms": NseTestData.now,
    ])

    let result = await harness.run()

    XCTAssertEqual(result, NseResult(delivery: .passthrough, outcome: .noMeta))
    XCTAssertTrue(harness.transport.requests.isEmpty)
    XCTAssertTrue(harness.best.values.isEmpty)
    XCTAssertNil(harness.files.read(NotifyFile.shownNse))
  }

  func testTheExtensionVersionIsRecordedOnceForDiagnostics() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", .offline)
    harness.transport.reply("nse/fetch", .offline)

    _ = await harness.run()
    _ = await harness.run(
      NsePush(id: "p2", roomId: NseTestData.roomId, eventId: "$ev2", receivedMs: NseTestData.now))

    XCTAssertEqual(NseStateFile.decode(harness.files.read(NotifyFile.state)).version, "2.1 (40)")
    XCTAssertEqual(harness.files.writes(NotifyFile.state), 1)
  }

  func testTheNamesFloorIsTheBestAttemptBeforeAnyNetwork() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", .offline)

    _ = await harness.run()

    XCTAssertEqual(harness.best.values.first?.title, "Design team")
    XCTAssertEqual(harness.best.values.first?.body, "New message")
    XCTAssertEqual(harness.best.values.first?.interruption, .active)
  }

  func testAnUnencryptedMessageShowsWithItsNamesAndCountsInTheBadge() async {
    let harness = harness(
      meta: NseTestData.meta(["unread": ["tOther"]]),
      delivered: [NseTestData.delivered("1", t: "tThird", k: "msg")])
    harness.transport.reply(
      "nse/fetch",
      NseTestData.ok(NseTestData.event(content: ["msgtype": "m.text", "body": "Lunch?"])))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .shown)
    XCTAssertEqual(result.delivery.title, "Design team")
    XCTAssertEqual(result.delivery.body, "Alice: Lunch?")
    XCTAssertEqual(result.delivery.threadId, roomToken)
    XCTAssertEqual(result.delivery.userInfo["e"], eventToken)
    XCTAssertEqual(result.delivery.badge, 3)
    XCTAssertEqual(harness.files.json(NotifyFile.shownNse)?["e"], .array([.string(eventToken)]))
    XCTAssertEqual(harness.defaults.integer("nse.c.20260921.o.shown"), 1)
    XCTAssertEqual(harness.signals.logged, ["nse_shown t=t!abc:zu ms=0 lag=5000 safe=0"])
  }

  func testAnEventThatWasNeverFetchedLogsNoLag() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", .offline)

    _ = await harness.run()

    XCTAssertEqual(harness.signals.logged.count, 1)
    XCTAssertFalse(harness.signals.logged[0].contains("lag="))
  }

  func testOnlyAMessageAtNameAndMessageCarriesTheActions() async {
    for (level, category) in [("full", "message"), ("name", nil), ("none", nil)]
      as [(String, String?)]
    {
      let harness = harness(meta: NseTestData.meta(["level": level]))
      harness.transport.reply(
        "nse/fetch",
        NseTestData.ok(NseTestData.event(content: ["msgtype": "m.text", "body": "Lunch?"])))
      let result = await harness.run()
      XCTAssertEqual(result.delivery.category, category, level)
    }
  }

  func testARoomWithoutAReadModelFileIsNamedByTheServer() async {
    let harness = harness(room: nil)
    harness.transport.reply(
      "nse/fetch",
      NseTestData.ok(
        NseTestData.event(content: ["msgtype": "m.text", "body": "Lunch?"]), senderName: nil))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .shown)
    XCTAssertEqual(result.delivery.title, "Design team")
    XCTAssertEqual(result.delivery.body, "Alice: Lunch?")
    XCTAssertEqual(harness.best.values.first?.title, "Zuno")
  }

  func testMentionsOnlyTrustsTheServerHighlightForUnencryptedEvents() async {
    let harness = harness(meta: NseTestData.meta(["notify": "mentions"]))
    harness.transport.reply(
      "nse/fetch", NseTestData.ok(NseTestData.event(content: ["msgtype": "m.text", "body": "hi"])))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .quiet)
    XCTAssertEqual(result.delivery.interruption, .passive)
  }

  func testAnEventShownBeforeIsRepeatedQuietlyInPlaceOfItsCopy() async {
    let harness = harness(delivered: [NseTestData.delivered("old", e: eventToken)])
    harness.files.put(NotifyFile.shownApp, ["v": 1, "e": [eventToken]])

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .duplicate)
    XCTAssertEqual(result.delivery.removals, ["old"])
    XCTAssertEqual(result.delivery.interruption, .passive)
    XCTAssertTrue(harness.transport.requests.isEmpty)
  }

  func testAnEventTheAppShowedInFrontKeepsTheAppsLine() async {
    let harness = harness(delivered: [
      NseTestData.delivered(
        "app", t: nil, body: "Alice: Lunch?", threadId: roomToken,
        payloadEventId: NseTestData.eventId, pushed: false)
    ])
    harness.files.put(NotifyFile.shownApp, ["v": 1, "e": [eventToken]])

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .duplicate)
    XCTAssertEqual(result.delivery.body, "Alice: Lunch?")
    XCTAssertEqual(result.delivery.interruption, .passive)
    XCTAssertTrue(result.delivery.removals.isEmpty)
  }

  func testNothingNeverTouchesTheNetworkAndGoesQuietWhileARingIsLedgered() async {
    let quietHarness = harness(meta: NseTestData.meta(["level": "none"]))
    quietHarness.files.put(
      NotifyFile.ledger,
      [
        "v": 1,
        "calls": [
          [
            "uuid": "U", "t": roomToken, "state": "ringing", "source": "push",
            "ts": NseTestData.now - 5000,
          ]
        ],
      ])
    let loudHarness = harness(meta: NseTestData.meta(["level": "none"]))

    let quiet = await quietHarness.run()
    let loud = await loudHarness.run()

    XCTAssertEqual(quiet.outcome, .nothing)
    XCTAssertEqual(quiet.delivery.title, "Zuno")
    XCTAssertEqual(quiet.delivery.threadId, "zuno")
    XCTAssertEqual(quiet.delivery.interruption, .passive)
    XCTAssertEqual(loud.delivery.interruption, .active)
    XCTAssertTrue(quietHarness.transport.requests.isEmpty)
  }

  func testNothingNamesNoRoomAndRepostsNoEarlierCopyOfAnEventShownBefore() async {
    let harness = harness(
      meta: NseTestData.meta(["level": "none"]),
      delivered: [NseTestData.delivered("old", e: eventToken, body: "Alice: Lunch?")])
    harness.files.put(NotifyFile.shownApp, ["v": 1, "e": [eventToken]])

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .nothing)
    XCTAssertEqual(result.delivery.interruption, .passive)
    XCTAssertEqual(result.delivery.sound, .none)
    XCTAssertTrue(result.delivery.removals.isEmpty)
    XCTAssertEqual(harness.best.values.count, 1)
    for line in [result.delivery] + harness.best.values {
      XCTAssertEqual(line.title, "Zuno")
      XCTAssertEqual(line.body, "New message")
      XCTAssertEqual(line.threadId, "zuno")
    }
    XCTAssertTrue(harness.transport.requests.isEmpty)
  }

  func testAMissingOrExpiredCredentialIsALoudFloor() async {
    let none = NotifySecrets(rmKey: Data(), installKey: Data())
    let expired = NotifySecrets(
      rmKey: Data(), installKey: Data(), credential: "c", credentialExpiresTs: NseTestData.now)

    let missing = await harness(keychain: .ready(none)).run()
    let old = await harness(keychain: .ready(expired)).run()

    XCTAssertEqual(missing.outcome, .auth)
    XCTAssertEqual(old.outcome, .auth)
    XCTAssertEqual(old.delivery.interruption, .active)
  }

  func testFetchFailuresPickALoudOrQuietFloor() async {
    let cases: [(NseHttpResult, NseOutcome, NseDelivery.Interruption)] = [
      (NseFakeTransport.module(200, ["status": "gone"]), .gone, .passive),
      (NseFakeTransport.module(429, ["errcode": "M_LIMIT_EXCEEDED"]), .rateLimited, .passive),
      (NseFakeTransport.module(503, ["errcode": "IM.ZUNO.STARTING"]), .route, .active),
      (NseFakeTransport.module(401, ["errcode": "IM.ZUNO.BAD_CREDENTIAL"]), .auth, .active),
      (.response(status: 404, headers: [:], body: Data()), .route, .active),
      (.timeout, .net, .active),
    ]
    for (reply, outcome, interruption) in cases {
      let harness = harness()
      harness.transport.reply("nse/fetch", reply)
      let result = await harness.run()
      XCTAssertEqual(result.outcome, outcome)
      XCTAssertEqual(result.delivery.interruption, interruption)
      XCTAssertEqual(result.delivery.body, "New message")
    }
  }

  func testAnEncryptedMessageDecryptsWithTheExportedSession() async {
    let ciphertext = NseTestData.ciphertext(index: 5, tag: 1)
    let harness = harness(
      room: NseTestData.room(sessions: [session()]), plaintexts: [ciphertext: plaintext("Hi")])
    harness.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .shown)
    XCTAssertEqual(result.delivery.body, "Alice: Hi")
    XCTAssertEqual(NseStateFile.decode(harness.files.read(NotifyFile.state)).replay, ["s1|5"])
  }

  func testAReplayedSessionIndexIsADuplicate() async {
    let ciphertext = NseTestData.ciphertext(index: 5, tag: 1)
    let harness = harness(
      room: NseTestData.room(sessions: [session()]), plaintexts: [ciphertext: plaintext("Hi")])
    harness.files.put(NotifyFile.state, ["v": 1, "replay": ["s1|5"], "utd": [], "missed": []])
    harness.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .duplicate)
    XCTAssertEqual(harness.decryptor.calls, 0)
  }

  func testAMissingKeyIsALoudNamesFloorRecordedForGroundTruth() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .utd)
    XCTAssertEqual(result.delivery.body, "Alice: New message")
    XCTAssertEqual(result.delivery.interruption, .active)
    XCTAssertEqual(
      NseStateFile.decode(harness.files.read(NotifyFile.state)).utd,
      [NseUtd(room: NseTestData.roomId, event: NseTestData.eventId, ts: NseTestData.now)])
  }

  func testAMessageBeforeTheTrimPointIsAMissingKey() async {
    let harness = harness(room: NseTestData.room(sessions: [session(first: 9)]))
    harness.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .utd)
    XCTAssertEqual(harness.decryptor.calls, 0)
  }

  func testAFreshAppWaitsForTheExportThenDecrypts() async {
    let ciphertext = NseTestData.ciphertext(index: 5, tag: 1)
    let harness = harness(
      meta: NseTestData.meta(["heartbeat_ms": NseTestData.now - 3000]),
      plaintexts: [ciphertext: plaintext("Hi")])
    let files = harness.files
    let name = NotifyFile.room(roomToken)
    let exported =
      (try? JSONSerialization.data(
        withJSONObject: NseTestData.room(sessions: [session()]))) ?? Data()
    harness.clock.onWait { _ in _ = files.write(name, exported) }
    harness.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .shown)
    XCTAssertEqual(harness.clock.waits, ["2000:im.zuno.chat.readmodel.changed"])
  }

  func testASessionFromAnotherSenderOrRoomIsRefused() async {
    let ciphertext = NseTestData.ciphertext(index: 5, tag: 1)
    let wrongOwner = harness(room: NseTestData.room(sessions: [session(sender: "@eve:zuno.im")]))
    wrongOwner.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))
    let wrongRoom = harness(
      room: NseTestData.room(sessions: [session()]),
      plaintexts: [ciphertext: plaintext("Hi", room: "!other:zuno.im")])
    wrongRoom.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let owner = await wrongOwner.run()
    let room = await wrongRoom.run()

    XCTAssertEqual(owner.outcome, .mismatch)
    XCTAssertEqual(room.outcome, .mismatch)
    XCTAssertEqual(room.delivery.body, "Alice: New message")
  }

  func testSafeModeNeverDecrypts() async {
    let harness = harness(room: NseTestData.room(sessions: [session()]))
    harness.defaults.set(Double(NseTestData.now / 1000 + 600), forKey: Breadcrumbs.safeUntilKey)
    harness.transport.reply("nse/fetch", NseTestData.ok(encrypted(5)))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .safeMode)
    XCTAssertEqual(harness.decryptor.calls, 0)
    XCTAssertEqual(harness.signals.logged.last?.hasSuffix("safe=1"), true)
  }

  func testAReadReplyRemovesTheReadLinesAndPostsAQuietNotice() async {
    let harness = harness(delivered: [
      NseTestData.delivered("read", t: roomToken, o: 100),
      NseTestData.delivered("unread", t: roomToken, o: 300),
      NseTestData.delivered("elsewhere", t: "tOther", o: 100),
      NseTestData.delivered("app", t: roomToken, o: 100, pushed: false),
    ])
    harness.transport.reply(
      "nse/fetch", NseFakeTransport.module(200, ["status": "read", "receipt_ts": 200_000]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .read)
    XCTAssertEqual(result.delivery.removals, ["read"])
    XCTAssertEqual(result.delivery.interruption, .passive)
    XCTAssertEqual(result.delivery.userInfo["k"], "sys")
  }

  func testAReadReplyWithoutAReceiptRemovesNothing() async {
    let harness = harness(delivered: [NseTestData.delivered("line", t: roomToken, o: 100)])
    harness.transport.reply(
      "nse/fetch", NseFakeTransport.module(200, ["status": "read", "receipt_ts": 0]))

    let result = await harness.run()

    XCTAssertEqual(result.outcome, .read)
    XCTAssertTrue(result.delivery.removals.isEmpty)
  }

  func testAHiddenEventRepostsTheNewestLineOrSaysNewActivity() async {
    let reaction = NseTestData.event(
      type: "m.reaction",
      content: ["m.relates_to": ["rel_type": "m.annotation", "event_id": "$x", "key": "+1"]])
    let withLines = harness(delivered: [
      NseTestData.delivered("older", t: roomToken, dateMs: 1),
      NseTestData.delivered("newer", t: roomToken, dateMs: 2),
    ])
    withLines.transport.reply("nse/fetch", NseTestData.ok(reaction))
    let empty = harness()
    empty.transport.reply("nse/fetch", NseTestData.ok(reaction))

    let reposted = await withLines.run()
    let activity = await empty.run()

    XCTAssertEqual(reposted.outcome, .hidden)
    XCTAssertEqual(reposted.delivery.removals, ["newer"])
    XCTAssertEqual(activity.delivery.body, "New activity")
    XCTAssertEqual(activity.delivery.interruption, .passive)
  }

  func testAHiddenEventNeverRepostsTheNotSentNotice() async {
    let reaction = NseTestData.event(
      type: "m.reaction",
      content: ["m.relates_to": ["rel_type": "m.annotation", "event_id": "$x", "key": "+1"]])
    let notice = NseTestData.delivered(
      ReplyNotSentNotice.request(
        for: NotificationActionNotice(
          notificationId: "n1", title: "Design team", thread: roomToken, roomId: nil,
          roomToken: roomToken)),
      dateMs: 2)
    let withLine = harness(delivered: [
      NseTestData.delivered("older", t: roomToken, dateMs: 1), notice,
    ])
    withLine.transport.reply("nse/fetch", NseTestData.ok(reaction))
    let onlyNotice = harness(delivered: [notice])
    onlyNotice.transport.reply("nse/fetch", NseTestData.ok(reaction))

    let reposted = await withLine.run()
    let activity = await onlyNotice.run()

    XCTAssertEqual(reposted.delivery.removals, ["older"])
    XCTAssertEqual(activity.delivery.body, "New activity")
  }

  func testTheCrumbIsClearedAfterAFinishedPush() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", .offline)

    _ = await harness.run()

    XCTAssertTrue(harness.defaults.crumbs(Breadcrumbs.crumbsKey).isEmpty)
  }
}
