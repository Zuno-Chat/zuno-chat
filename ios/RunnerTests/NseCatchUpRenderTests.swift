import UserNotifications
import XCTest

@testable import Runner

final class NseCatchUpRenderTests: XCTestCase {
  private let roomToken = "t\(NseTestData.roomId)"

  private func makeHarness(level: String) -> NseHarness {
    let harness = NseHarness()
    harness.files.put(NotifyFile.meta, NseTestData.meta(["level": level]))
    harness.files.put(NotifyFile.room(roomToken), NseTestData.room())
    return harness
  }

  private func render(
    _ event: [String: Any], level: String = "full", decrypt: Bool = true,
    in given: NseHarness? = nil
  ) throws -> CatchUpRender {
    let harness = given ?? makeHarness(level: level)
    let store = NseStateStore(files: harness.files)
    let meta = try XCTUnwrap(store.meta())
    let context = NseContext(
      push: NseTestData.push(eventId: "$pushed"), roomId: NseTestData.roomId,
      eventId: "$pushed", keys: NseTestData.keys, store: store, hashing: NseFakeHashing(),
      meta: meta, t: roomToken, e: "e$pushed", start: NseTestData.now, room: nil)
    let item = try XCTUnwrap(
      MissedEvent(json: [
        "room_id": NseTestData.roomId, "event_id": NseTestData.eventId, "event": event,
        "is_dm": false, "highlight": false, "sound": true,
      ]))
    return NsePipeline(env: harness.environment).renderCatchUp(
      item, decrypt: decrypt, context: context)
  }

  func testAMissedMessageIsComposedAtTheLevel() throws {
    let event = NseTestData.event(content: ["msgtype": "m.text", "body": "Lunch?"])
    XCTAssertEqual(
      try render(event), .shown(title: "Design team", body: "Alice: Lunch?", kind: "msg"))
    XCTAssertEqual(
      try render(event, level: "name"),
      .shown(title: "Design team", body: "Alice: New message", kind: "msg"))
  }

  func testAnEncryptedItemThatIsNotDecryptedIsAFloor() throws {
    let event = NseTestData.event(
      type: "m.room.encrypted",
      content: [
        "algorithm": "m.megolm.v1.aes-sha2", "session_id": "s1",
        "ciphertext": NseTestData.ciphertext(index: 0, tag: 1),
      ])
    XCTAssertEqual(
      try render(event, decrypt: false),
      .shown(title: "Design team", body: "Alice: New message", kind: "msg", floor: true))
  }

  func testAMissedCallShowsOnceAndARingNever() throws {
    let harness = makeHarness(level: "full")
    let summary = NseTestData.event(content: [
      "msgtype": "im.zuno.call_summary", "call_id": "c9", "kind": "voice", "status": "missed",
      "body": "Missed call",
    ])
    XCTAssertEqual(
      try render(summary, in: harness),
      .shown(title: "Design team", body: "Alice: Missed Voice call", kind: "msg"))
    XCTAssertEqual(try render(summary, in: harness), .hidden)
    let ring = NseTestData.event(content: [
      "msgtype": "im.zuno.call_invite", "call_id": "c1", "kind": "voice",
    ])
    XCTAssertEqual(try render(ring), .hidden)
  }

  func testAnInvitationShowsOnceAndAVerificationRequestAsksToVerify() throws {
    let harness = makeHarness(level: "full")
    let invite = NseTestData.event(
      type: "m.room.member", content: ["membership": "invite"], stateKey: NseTestData.me)
    XCTAssertEqual(
      try render(invite, in: harness),
      .shown(title: "Alice", body: "Invited you to chat", kind: "inv"))
    XCTAssertEqual(try render(invite, in: harness), .hidden)
    let verification = NseTestData.event(content: [
      "msgtype": "m.key.verification.request", "to": NseTestData.me,
    ])
    XCTAssertEqual(
      try render(verification),
      .shown(title: "Alice", body: "Wants to verify you", kind: "sys"))
  }

  func testTextIsCleanedAndCappedLikeEveryOtherLine() throws {
    let text = "Hi\u{7}" + String(repeating: "a", count: 400)
    let event = NseTestData.event(content: ["msgtype": "m.text", "body": text])
    guard case .shown(_, let body, _, _) = try render(event) else { return XCTFail("hidden") }
    XCTAssertEqual(body.unicodeScalars.count, NseComposer.maxCharacters)
    XCTAssertFalse(body.unicodeScalars.contains("\u{7}"))
    XCTAssertTrue(body.hasPrefix("Alice: Hi"))
  }
}

private final class CatchUpCalls: @unchecked Sendable {
  var runs = 0
  var delivered: [DeliveredNote] = []
  var removed: [[String]] = []
  var posted: [UNNotificationRequest] = []
}

private final class RecordingCatchUpPlatform: CatchUpPlatform {
  private let sources: NseCatchUpPlatform.Sources
  private let calls: CatchUpCalls

  init(_ sources: NseCatchUpPlatform.Sources, _ calls: CatchUpCalls) {
    self.sources = sources
    self.calls = calls
    calls.runs += 1
  }

  func roomToken(_ roomId: String) -> String? { sources.roomToken(roomId) }
  func eventToken(_ eventId: String) -> String? { sources.eventToken(eventId) }
  func alreadyShown(_ eventToken: String) -> Bool { sources.alreadyShown(eventToken) }
  func availableMemory() -> Int { CatchUp.decryptFloorBytes }

  func render(_ event: MissedEvent, decrypt: Bool) -> CatchUpRender {
    sources.render(event, decrypt)
  }

  func delivered() async -> [DeliveredNote] { calls.delivered }
  func remove(_ identifiers: [String]) { calls.removed.append(identifiers) }

  func post(_ request: UNNotificationRequest) async -> Bool {
    calls.posted.append(request)
    return true
  }

  func recordShown(_ eventTokens: [String]) { sources.recordShown(eventTokens) }
  func now() -> Date { Date() }
}

final class NsePipelineCatchUpTests: XCTestCase {
  private let otherRoom = "!other:zuno.im"

  private func harness(unread: [String] = [], delivered: [NseDelivered] = []) -> NseHarness {
    let harness = NseHarness(delivered: delivered)
    harness.files.put(NotifyFile.meta, NseTestData.meta(["unread": unread]))
    harness.files.put(NotifyFile.room("t\(NseTestData.roomId)"), NseTestData.room())
    return harness
  }

  private func missed(_ eventId: String, in roomId: String) -> [String: Any] {
    var event = NseTestData.event(
      content: ["msgtype": "m.text", "body": "Later"], eventId: eventId)
    event["room_id"] = roomId
    return [
      "room_id": roomId, "event_id": eventId, "event": event, "is_dm": false,
      "highlight": false, "sound": true,
    ]
  }

  private func reply(_ status: String = "ok", extras: [String: Any]) -> NseHttpResult {
    var body: [String: Any] = ["status": status, "server_ts": NseTestData.now]
    if status == "ok" {
      body["event"] = NseTestData.event(content: ["msgtype": "m.text", "body": "Lunch?"])
      body["sender_name"] = "Alice"
      body["room_name"] = "Design team"
      body["is_dm"] = false
      body["highlight"] = false
      body["sound"] = true
    }
    if status == "read" { body["receipt_ts"] = NseTestData.now }
    for (key, value) in extras { body[key] = value }
    return NseFakeTransport.module(200, body)
  }

  private func run(_ harness: NseHarness, _ calls: CatchUpCalls) async -> NseResult {
    var environment = harness.environment
    environment.catchUpPlatform = { RecordingCatchUpPlatform($0, calls) }
    return await NsePipeline(env: environment).run(NseTestData.push()) { _ in }
  }

  func testMissedEventsArePostedOnceAndRecordedAsShown() async {
    let harness = harness()
    harness.transport.reply(
      "nse/fetch", reply(extras: ["missed": [missed("$m1:zuno.im", in: otherRoom)]]))
    let calls = CatchUpCalls()
    _ = await run(harness, calls)
    XCTAssertEqual(calls.runs, 1)
    XCTAssertEqual(calls.posted.map(\.identifier), ["zuno.catchup.e$m1:zuno.im"])
    XCTAssertTrue(NseStateStore(files: harness.files).isShown("e$m1:zuno.im"))
  }

  func testTheBadgeDropsRoomsReadElsewhereAndKeepsThePushedRoom() async {
    let readRoom = "!read:zuno.im"
    let seconds = NseTestData.now / 1000 - 60
    let harness = harness(
      unread: ["t\(readRoom)", "t\(NseTestData.roomId)"],
      delivered: [NseTestData.delivered("old", t: "t\(readRoom)", o: seconds)])
    harness.transport.reply(
      "nse/fetch",
      reply(extras: [
        "missed": [missed("$m1:zuno.im", in: otherRoom)],
        "read_rooms": [
          ["room_id": readRoom, "receipt_ts": NseTestData.now],
          ["room_id": NseTestData.roomId, "receipt_ts": NseTestData.now],
        ],
      ]))
    let calls = CatchUpCalls()
    calls.delivered = [
      DeliveredNote(
        identifier: "old", thread: "t\(readRoom)", roomToken: "t\(readRoom)",
        seconds: Int(seconds))
    ]
    let result = await run(harness, calls)
    XCTAssertEqual(calls.removed, [["old"]])
    XCTAssertEqual(result.delivery.badge, 2)
  }

  func testWorkStopsTwentyTwoSecondsAfterTheRunStarted() async {
    let harness = harness()
    harness.transport.reply(
      "nse/fetch", reply(extras: ["missed": [missed("$m1:zuno.im", in: otherRoom)]]),
      after: 23_000)
    let calls = CatchUpCalls()
    _ = await run(harness, calls)
    XCTAssertEqual(calls.runs, 1)
    XCTAssertTrue(calls.posted.isEmpty)
  }

  func testReadAndGoneRepliesCatchUpToo() async {
    for status in ["read", "gone"] {
      let harness = harness()
      harness.transport.reply(
        "nse/fetch", reply(status, extras: ["missed": [missed("$m1:zuno.im", in: otherRoom)]]))
      let calls = CatchUpCalls()
      _ = await run(harness, calls)
      XCTAssertEqual(calls.runs, 1, status)
    }
  }

  func testOneLogLineCarriesTheCatchUpCountsAndNothingElse() async {
    let harness = harness()
    harness.transport.reply(
      "nse/fetch",
      reply(extras: [
        "missed": [missed("$m1:zuno.im", in: otherRoom)],
        "read_rooms": [["room_id": "!read:zuno.im", "receipt_ts": NseTestData.now]],
      ]))
    _ = await run(harness, CatchUpCalls())
    XCTAssertEqual(
      harness.signals.logged.filter { $0.hasPrefix("nse_catchup") },
      ["nse_catchup posted=1 hidden=0 read=1 overflow=0 floor=0"])
  }

  func testEmptyExtrasLeaveNoCatchUpLogLine() async {
    let harness = harness()
    harness.transport.reply("nse/fetch", reply(extras: ["missed": [], "read_rooms": []]))
    _ = await run(harness, CatchUpCalls())
    XCTAssertEqual(harness.signals.logged.filter { $0.hasPrefix("nse_catchup") }, [])
  }

  func testAReplyWithoutExtrasOrAFailedFetchCatchesNothingUp() async {
    let calls = CatchUpCalls()
    let plain = harness()
    plain.transport.reply(
      "nse/fetch",
      NseTestData.ok(NseTestData.event(content: ["msgtype": "m.text", "body": "Lunch?"])))
    _ = await run(plain, calls)
    _ = await run(harness(), calls)
    XCTAssertEqual(calls.runs, 0)
  }
}
