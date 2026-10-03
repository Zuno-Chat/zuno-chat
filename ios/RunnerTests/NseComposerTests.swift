import XCTest

@testable import Runner

final class NseComposerTests: XCTestCase {
  private let tokens = NseTokens(t: "t1", e: "e1", o: 1_790_000_000)
  private let room = NseNames(title: "Design team", sender: "Alice", isDm: false)
  private let chat = NseNames(title: "Alice", sender: "Alice", isDm: true)

  func testNameAndMessageShowsTheTextUnderOpaqueIds() {
    let delivery = NseComposer.message(
      text: "Lunch?", keepsTextWhenNameOnly: false, names: room, level: .full, loud: true,
      tone: true, tokens: tokens)

    XCTAssertEqual(delivery.title, "Design team")
    XCTAssertEqual(delivery.body, "Alice: Lunch?")
    XCTAssertEqual(delivery.threadId, "t1")
    XCTAssertEqual(delivery.userInfo, ["t": "t1", "e": "e1", "o": "1790000000", "k": "msg"])
    XCTAssertEqual(delivery.interruption, .active)
    XCTAssertEqual(delivery.sound, .messageTone)
  }

  func testNameOnlyHidesTheTextButKeepsAMissedCall() {
    let hidden = NseComposer.message(
      text: "Lunch?", keepsTextWhenNameOnly: false, names: chat, level: .name, loud: true,
      tone: true, tokens: tokens)
    let missed = NseComposer.message(
      text: "Missed Voice call", keepsTextWhenNameOnly: true, names: chat, level: .name,
      loud: true, tone: true, tokens: tokens)

    XCTAssertEqual(hidden.body, "New message")
    XCTAssertEqual(missed.body, "Missed Voice call")
  }

  func testAQuietOrToneOffLinePlaysNothing() {
    let quiet = NseComposer.message(
      text: "hi", keepsTextWhenNameOnly: false, names: chat, level: .full, loud: false,
      tone: true, tokens: tokens)
    let toneOff = NseComposer.message(
      text: "hi", keepsTextWhenNameOnly: false, names: chat, level: .full, loud: true,
      tone: false, tokens: tokens)

    XCTAssertEqual(quiet.interruption, .passive)
    XCTAssertEqual(quiet.sound, .none)
    XCTAssertEqual(toneOff.interruption, .active)
    XCTAssertEqual(toneOff.sound, .none)
  }

  func testTheFloorNamesTheSenderOnlyInARoom() {
    let inRoom = NseComposer.floor(
      names: room, level: .full, loud: true, tone: true, tokens: tokens)
    let inChat = NseComposer.floor(
      names: chat, level: .full, loud: true, tone: true, tokens: tokens)

    XCTAssertEqual(inRoom.body, "Alice: New message")
    XCTAssertEqual(inChat.body, "New message")
    XCTAssertEqual(inRoom.userInfo["f"], "1")
  }

  func testNothingIsGenericOnOneFixedThread() {
    let loud = NseComposer.nothing(tokens: tokens, quiet: false, tone: true)
    let quiet = NseComposer.nothing(tokens: tokens, quiet: true, tone: true)

    XCTAssertEqual(loud.title, "Zuno")
    XCTAssertEqual(loud.body, "New message")
    XCTAssertEqual(loud.threadId, "zuno")
    XCTAssertEqual(loud.sound, .messageTone)
    XCTAssertEqual(quiet.interruption, .passive)
    let threads = [PreviewLevel.full, PreviewLevel.none].flatMap { level in
      [
        NseComposer.floor(names: room, level: level, loud: true, tone: true, tokens: tokens),
        NseComposer.activity(names: room, level: level, video: nil, tokens: tokens),
      ].map(\.threadId)
    }
    XCTAssertEqual(threads, ["t1", "t1", "zuno", "zuno"])
  }

  func testTheFallbackRingIsTimeSensitiveAndFollowsTheRingtone() {
    let ring = NseComposer.fallbackRing(
      names: chat, video: true, ringtone: true, tokens: tokens, rg: "r1")
    let silent = NseComposer.fallbackRing(
      names: chat, video: false, ringtone: false, tokens: tokens, rg: "r1")

    XCTAssertEqual(ring.body, "Incoming video call")
    XCTAssertEqual(ring.interruption, .timeSensitive)
    XCTAssertEqual(ring.sound, .ring)
    XCTAssertEqual(ring.userInfo["rg"], "r1")
    XCTAssertEqual(ring.userInfo["k"], "call")
    XCTAssertEqual(silent.body, "Incoming voice call")
    XCTAssertEqual(silent.sound, .silentRing)
  }

  func testNamesComeFromTheReadModelThenTheServerThenTheLocalpart() {
    let file = NseRoomFile(
      room: "!r", title: "Book club", dm: false, partner: nil, sessions: [], notifiers: [])
    let event = NseEvent(
      eventId: "$e", roomId: "!r", type: "m.room.message", sender: "@sam_lee:zuno.im",
      originServerTs: 0)
    let fetched = NseFetched(
      event: event, senderName: nil, roomName: "Server name", isDm: false, highlight: false,
      serverTs: nil)

    XCTAssertEqual(
      NseComposer.names(room: file, fetched: fetched, senderId: event.sender),
      NseNames(title: "Book club", sender: "Sam Lee", isDm: false))
    XCTAssertEqual(
      NseComposer.names(room: nil, fetched: fetched, senderId: event.sender).title, "Server name")
    XCTAssertEqual(NseComposer.names(room: nil, fetched: nil, senderId: nil).title, "Zuno")
  }

  func testNamesFollowTheSharedNameVectors() throws {
    for item in try NseFixtures.cases("names_v1.json") {
      let input = try XCTUnwrap(item["input"]?.string)
      XCTAssertEqual(
        NseComposer.name(input), item["output"]?.string, item["name"]?.string ?? "")
    }
  }

  func testNamesFromTheServerAreNormalizedLikeTheReadModel() {
    let event = NseEvent(
      eventId: "$e", roomId: "!r", type: "m.room.message", sender: "@sam:zuno.im",
      originServerTs: 0)
    let fetched = NseFetched(
      event: event, senderName: "\u{202E}Sam\u{0000}" + String(repeating: "m", count: 80),
      roomName: nil, isDm: true, highlight: false, serverTs: nil)

    let names = NseComposer.names(room: nil, fetched: fetched, senderId: event.sender)

    XCTAssertEqual(names.sender.utf8.count, 64)
    XCTAssertTrue(names.sender.hasPrefix("Sammm"))
  }

  func testTextLosesControlAndDirectionCharactersAndStopsAt300() {
    XCTAssertEqual(NseComposer.sanitize("a\u{202E}b\u{0007}c\nd"), "abc\nd")
    let long = NseComposer.sanitize(String(repeating: "x", count: 400))
    XCTAssertEqual(long.count, 300)
    XCTAssertTrue(long.hasSuffix("…"))
  }

  func testCombiningMarksCannotCarryAnEndlessTextPastTheCap() {
    let text = NseComposer.sanitize("e" + String(repeating: "\u{0301}", count: 50_000))

    XCTAssertEqual(text.unicodeScalars.count, 300)
    XCTAssertTrue(text.hasSuffix("…"))
  }

  func testBlankNamesFallBackLikeEmptyOnes() {
    let file = NseRoomFile(
      room: "!r", title: " ", dm: false, partner: nil, sessions: [], notifiers: [])
    let event = NseEvent(
      eventId: "$e", roomId: "!r", type: "m.room.message", sender: "@sam_lee:zuno.im",
      originServerTs: 0)
    let fetched = NseFetched(
      event: event, senderName: "\u{3000}", roomName: "Server name", isDm: false,
      highlight: false, serverTs: nil)

    XCTAssertEqual(
      NseComposer.names(room: file, fetched: fetched, senderId: event.sender),
      NseNames(title: "Server name", sender: "Sam Lee", isDm: false))
  }

  func testAnInvitationRoomNameIsNormalizedAndABlankOneIsLeftOut() {
    let long = NseComposer.invitationLines(
      inviter: "Alice", roomName: "\u{202E}" + String(repeating: "r", count: 80))
    let blank = NseComposer.invitationLines(inviter: "Alice", roomName: " ")

    XCTAssertEqual(long.body, "Invited you to " + String(repeating: "r", count: 64))
    XCTAssertEqual(blank.body, "Invited you to chat")
  }

  func testTheNothingLevelShowsNoSenderRoomOrMessageText() {
    let loud = NseComposer.message(
      text: "Missed Voice call", keepsTextWhenNameOnly: true, names: room, level: .none,
      loud: true, tone: true, tokens: tokens)
    let quiet = NseComposer.message(
      text: "Lunch?", keepsTextWhenNameOnly: false, names: chat, level: .none, loud: false,
      tone: true, tokens: tokens)

    XCTAssertEqual(loud, NseComposer.nothing(tokens: tokens, quiet: false, tone: true))
    XCTAssertEqual(quiet, NseComposer.nothing(tokens: tokens, quiet: true, tone: true))
    for shown in ["Missed", "Voice", "Alice", "Design", "Lunch"] {
      XCTAssertFalse(loud.title.contains(shown) || loud.body.contains(shown))
      XCTAssertFalse(quiet.title.contains(shown) || quiet.body.contains(shown))
    }
  }

  func testLocalpartsAreNamedLikeTheSdkHistoricalOnesIncluded() {
    XCTAssertEqual(NseComposer.formattedLocalpart("@Alice:zuno.im"), "Alice")
    XCTAssertEqual(NseComposer.formattedLocalpart("@a_b_c:zuno.im"), "A B C")
    XCTAssertEqual(NseComposer.formattedLocalpart("alice"), "")
    XCTAssertEqual(NseComposer.formattedLocalpart("@alice:"), "")
    XCTAssertEqual(NseComposer.formattedLocalpart("@alice"), "")
  }

  func testTheTestLineIsMarkedSoZunoShowsItInFront() {
    XCTAssertEqual(NseComposer.test().userInfo, ["k": "sys", "test": "1"])
  }

  func testTheBadgeCountsUnreadRoomsAndDeliveredMessagesAndInvitations() {
    let delivered = [
      NseTestData.delivered("1", t: "t2", k: "msg"),
      NseTestData.delivered("2", t: "t3", k: "inv"),
      NseTestData.delivered("3", t: "t4", k: "call"),
      NseTestData.delivered("4", t: "t5", k: "sys"),
      NseTestData.delivered("5", t: "t6", k: "msg"),
    ]

    XCTAssertEqual(
      NseComposer.badge(
        unread: ["t1", "t2"], delivered: delivered, removed: ["5"], current: ("t7", true)),
      4)
    XCTAssertEqual(
      NseComposer.badge(unread: [], delivered: [], removed: [], current: ("t7", false)), 0)
    XCTAssertNil(NseComposer.badge(unread: nil, delivered: delivered, removed: [], current: nil))
  }

  func testARepostIsQuietAndReplacesItsOriginal() {
    let earlier = NseTestData.delivered("old", e: "e9")
    let repost = NseComposer.repost(earlier, tokens: NseTokens(t: "t1", e: "e1", o: 5))

    XCTAssertEqual(repost.title, earlier.title)
    XCTAssertEqual(repost.userInfo, earlier.userInfo)
    XCTAssertEqual(repost.interruption, .passive)
    XCTAssertEqual(repost.sound, .none)
    XCTAssertEqual(repost.removals, ["old"])
  }

  func testARepostOfTheAppsOwnLineLeavesItInPlace() {
    let local = NseTestData.delivered("app", t: nil, threadId: "t1", pushed: false)
    let repost = NseComposer.repost(local, tokens: NseTokens(t: "t1", e: "e1", o: 5))

    XCTAssertEqual(repost.body, local.body)
    XCTAssertEqual(repost.threadId, "t1")
    XCTAssertEqual(repost.userInfo, ["t": "t1", "e": "e1", "o": "5", "k": "msg"])
    XCTAssertTrue(repost.removals.isEmpty)
  }
}
