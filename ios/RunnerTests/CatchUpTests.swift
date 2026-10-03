import UserNotifications
import XCTest

@testable import Runner

private final class FakeCatchUpPlatform: CatchUpPlatform {
  var memory = 50 * 1024 * 1024
  var shown: Set<String> = []
  var renders: [String: CatchUpRender] = [:]
  var deliveredNotes: [DeliveredNote] = []
  var refusesPosts = false
  var showsMeanwhile: [String: String] = [:]
  var tickPerPost: TimeInterval = 0
  private(set) var clock: Date
  private(set) var decrypted: [String: Bool] = [:]
  private(set) var posted: [UNNotificationRequest] = []
  private(set) var removed: [[String]] = []
  private(set) var recorded: [[String]] = []
  private(set) var deliveredReads = 0
  private(set) var log: [String] = []

  init(now: Date) { clock = now }

  func roomToken(_ roomId: String) -> String? { "t" + roomId }
  func eventToken(_ eventId: String) -> String? { "e" + eventId }
  func alreadyShown(_ eventToken: String) -> Bool { shown.contains(eventToken) }
  func availableMemory() -> Int { memory }

  func render(_ event: MissedEvent, decrypt: Bool) -> CatchUpRender {
    decrypted[event.eventId] = decrypt
    if let token = showsMeanwhile[event.eventId] { shown.insert(token) }
    return renders[event.eventId]
      ?? .shown(title: "Alice", body: "hi \(event.eventId)", kind: "msg")
  }

  func delivered() async -> [DeliveredNote] {
    deliveredReads += 1
    return deliveredNotes
  }

  func remove(_ identifiers: [String]) {
    log.append("remove")
    removed.append(identifiers)
  }

  func post(_ request: UNNotificationRequest) async -> Bool {
    clock = clock.addingTimeInterval(tickPerPost)
    if refusesPosts { return false }
    log.append("post")
    posted.append(request)
    return true
  }

  func recordShown(_ eventTokens: [String]) { recorded.append(eventTokens) }
  func now() -> Date { clock }
}

final class CatchUpTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_790_000_000)

  private func body(
    _ events: [(room: String, event: String, seconds: Int64, dm: Bool)],
    reads: [(room: String, receiptMs: Int64)] = []
  ) -> [String: Any] {
    let missed: [[String: Any]] = events.map { entry -> [String: Any] in
      [
        "room_id": entry.room, "event_id": entry.event, "is_dm": entry.dm,
        "event": ["origin_server_ts": entry.seconds * 1000] as [String: Any],
      ]
    }
    let readRooms: [[String: Any]] = reads.map { entry -> [String: Any] in
      ["room_id": entry.room, "receipt_ts": entry.receiptMs]
    }
    return ["status": "ok", "missed": missed, "read_rooms": readRooms]
  }

  private func run(
    _ platform: FakeCatchUpPlatform, _ body: [String: Any], level: String = "full",
    budget: TimeInterval = 22
  ) async -> CatchUpOutcome {
    await CatchUp.run(
      body: body, level: level, pushedEventId: "$pushed",
      deadline: start.addingTimeInterval(budget), platform: platform)
  }

  func testEachMissedEventIsPostedQuietlyOldestFirstWithTheBusiestRoomLast() async {
    let platform = FakeCatchUpPlatform(now: start)
    _ = await run(
      platform,
      body([
        ("!a:hs", "$a2", 200, false), ("!b:hs", "$b1", 150, true), ("!a:hs", "$a1", 100, false),
      ]))
    XCTAssertEqual(
      platform.posted.map(\.identifier),
      ["zuno.catchup.e$b1", "zuno.catchup.e$a1", "zuno.catchup.e$a2"])
    XCTAssertEqual(
      platform.posted.map(\.content.threadIdentifier), ["t!b:hs", "t!a:hs", "t!a:hs"])
    XCTAssertTrue(
      platform.posted.allSatisfy {
        $0.content.interruptionLevel == .passive && $0.content.sound == nil
      })
  }

  func testPostedEventsAreRecordedAsShownInOneWrite() async {
    let platform = FakeCatchUpPlatform(now: start)
    _ = await run(platform, body([("!a:hs", "$a1", 100, false), ("!b:hs", "$b1", 90, false)]))
    XCTAssertEqual(platform.recorded, [["e$b1", "e$a1"]])
  }

  func testHiddenEventsAreNeitherPostedNorRecorded() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.renders["$a1"] = .hidden
    _ = await run(platform, body([("!a:hs", "$a1", 100, false), ("!b:hs", "$b1", 90, false)]))
    XCTAssertEqual(platform.posted.map(\.identifier), ["zuno.catchup.e$b1"])
    XCTAssertEqual(platform.recorded, [["e$b1"]])
  }

  func testBelowSixMegabytesOfFreeMemoryEventsAreShownWithoutDecrypting() async {
    let low = FakeCatchUpPlatform(now: start)
    low.memory = 6 * 1024 * 1024 - 1
    _ = await run(low, body([("!a:hs", "$a1", 100, false)]))
    XCTAssertEqual(low.decrypted["$a1"], false)

    let enough = FakeCatchUpPlatform(now: start)
    enough.memory = 6 * 1024 * 1024
    _ = await run(enough, body([("!a:hs", "$a1", 100, false)]))
    XCTAssertEqual(enough.decrypted["$a1"], true)
  }

  func testNothingIsPostedOnceTheDeadlinePasses() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.tickPerPost = 10
    let events = (1...4).map { (room: "!a:hs", event: "$a\($0)", seconds: Int64($0), dm: false) }
    _ = await run(platform, body(events))
    XCTAssertEqual(platform.posted.count, 3)
  }

  func testReadRoomsLoseTheirNotificationsUpToTheReceiptBeforeAnythingIsPosted() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.deliveredNotes = [
      DeliveredNote(identifier: "old", thread: "t!r:hs", roomToken: "t!r:hs", seconds: 100),
      DeliveredNote(identifier: "new", thread: "t!r:hs", roomToken: "t!r:hs", seconds: 300),
      DeliveredNote(identifier: "other", thread: "t!o:hs", roomToken: "t!o:hs", seconds: 100),
    ]
    let outcome = await run(
      platform, body([("!x:hs", "$x1", 400, false)], reads: [("!r:hs", 200_999)]))
    XCTAssertEqual(platform.removed, [["old"]])
    XCTAssertEqual(platform.log, ["remove", "post"])
    XCTAssertEqual(outcome.readRoomTokens, ["t!r:hs"])
    XCTAssertEqual(outcome.removed, ["old"])
  }

  func testAReadRoomWithoutAKnownReceiptRemovesNothing() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.deliveredNotes = [
      DeliveredNote(identifier: "old", thread: "t!r:hs", roomToken: "t!r:hs", seconds: 100)
    ]
    let outcome = await run(platform, body([], reads: [("!r:hs", 0)]))
    XCTAssertEqual(platform.deliveredReads, 0)
    XCTAssertTrue(platform.removed.isEmpty)
    XCTAssertTrue(outcome.readRoomTokens.isEmpty)
  }

  func testAtNothingNoMessageIsPosted() async {
    let platform = FakeCatchUpPlatform(now: start)
    let outcome = await run(platform, body([("!a:hs", "$a1", 100, false)]), level: "none")
    XCTAssertTrue(platform.posted.isEmpty)
    XCTAssertTrue(platform.recorded.isEmpty)
    XCTAssertEqual(outcome.unreadRoomTokens, ["t!a:hs"])
  }

  func testAReplyWithoutExtrasTouchesNoNotification() async {
    let platform = FakeCatchUpPlatform(now: start)
    let outcome = await run(platform, ["status": "gone", "server_ts": 1])
    XCTAssertEqual(platform.deliveredReads, 0)
    XCTAssertTrue(platform.removed.isEmpty)
    XCTAssertTrue(platform.posted.isEmpty)
    XCTAssertEqual(outcome, CatchUpOutcome())
  }

  func testRoomsPastTheTenthBecomeOneQuietSummary() async {
    let platform = FakeCatchUpPlatform(now: start)
    var events = (0..<10).map {
      (room: "!r\($0):hs", event: "$r\($0)", seconds: 1000 + Int64($0), dm: false)
    }
    events.append((room: "!chat:hs", event: "$c1", seconds: 10, dm: true))
    events.append((room: "!room:hs", event: "$m1", seconds: 20, dm: false))
    _ = await run(platform, body(events))
    XCTAssertEqual(platform.posted.count, 11)
    XCTAssertEqual(platform.posted.first?.identifier, "zuno.catchup.more")
    XCTAssertEqual(platform.posted.first?.content.body, "New messages in 2 more chats and rooms")
  }

  func testTheOutcomeCountsWhatWasHiddenFlooredAndLeftToTheSummary() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.renders["$r5"] = .hidden
    platform.renders["$r6"] = .shown(title: "Alice", body: "New message", kind: "msg", floor: true)
    let events = (0..<12).map {
      (room: "!r\($0):hs", event: "$r\($0)", seconds: 1000 + Int64($0), dm: false)
    }
    let outcome = await run(platform, body(events))
    XCTAssertEqual(outcome.posted, 9)
    XCTAssertEqual(outcome.hidden, 1)
    XCTAssertEqual(outcome.floors, 1)
    XCTAssertEqual(outcome.overflow, 2)
  }

  func testAnEventAnotherRunShowedMeanwhileIsNotPostedAgain() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.showsMeanwhile["$a1"] = "e$a2"
    let outcome = await run(
      platform, body([("!a:hs", "$a1", 100, false), ("!a:hs", "$a2", 200, false)]))
    XCTAssertEqual(platform.posted.map(\.identifier), ["zuno.catchup.e$a1"])
    XCTAssertEqual(platform.recorded, [["e$a1"]])
    XCTAssertEqual(outcome.posted, 1)
    XCTAssertEqual(outcome.hidden, 0)
  }

  func testAPostTheSystemRefusedIsNotRecordedAsShown() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.refusesPosts = true
    let outcome = await run(platform, body([("!a:hs", "$a1", 100, false)]))
    XCTAssertTrue(platform.recorded.isEmpty)
    XCTAssertEqual(outcome.posted, 0)
  }

  func testTheOutcomeNamesTheUnreadRoomsForTheBadge() async {
    let platform = FakeCatchUpPlatform(now: start)
    platform.shown = ["e$b1"]
    let outcome = await run(
      platform, body([("!a:hs", "$a1", 100, false), ("!b:hs", "$b1", 90, false)]))
    XCTAssertEqual(outcome.unreadRoomTokens, ["t!a:hs", "t!b:hs"])
    XCTAssertEqual(outcome.posted, 1)
  }

  func testTheBadgeDropsRoomsReadElsewhereUnlessTheyHaveUnreadEventsAgain() {
    let outcome = CatchUpOutcome(
      readRoomTokens: ["t1", "t2"], unreadRoomTokens: ["t2", "t4"], posted: 0, removed: [])
    XCTAssertEqual(CatchUpBadge.unread(["t1", "t2", "t3"], after: outcome), ["t2", "t3", "t4"])
    XCTAssertEqual(CatchUpBadge.unread(["t1"], after: CatchUpOutcome()), ["t1"])
  }
}
