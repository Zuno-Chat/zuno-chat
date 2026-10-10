import UserNotifications
import XCTest

@testable import Runner

final class DeliveredSweepTests: XCTestCase {
  private func note(
    _ identifier: String, token: String? = "t1", thread: String = "t1", seconds: Int? = 100,
    appPosted: Bool = false, roomId: String? = nil
  ) -> DeliveredNote {
    DeliveredNote(
      identifier: identifier, thread: thread, roomToken: token, seconds: seconds,
      appPosted: appPosted, roomId: roomId)
  }

  func testAReadRoomLosesItsNotificationsUpToTheReceipt() {
    let removed = DeliveredSweep.identifiersToRemove(
      [note("a", seconds: 100), note("b", seconds: 101), note("c", seconds: 102)],
      reads: [ThreadRead(token: "t1", upToMs: 101_500)])
    XCTAssertEqual(removed, ["a", "b"])
  }

  func testOtherRoomsKeepTheirNotifications() {
    let removed = DeliveredSweep.identifiersToRemove(
      [note("a"), note("b", token: "t2", thread: "t2")],
      reads: [ThreadRead(token: "t1", upToMs: nil)])
    XCTAssertEqual(removed, ["a"])
  }

  func testANotificationWithoutAnEventTimeStaysUntilTheWholeThreadIsRead() {
    let timeless = note("a", seconds: nil)
    XCTAssertEqual(
      DeliveredSweep.identifiersToRemove(
        [timeless], reads: [ThreadRead(token: "t1", upToMs: 9_999_999_999)]), [])
    XCTAssertEqual(
      DeliveredSweep.identifiersToRemove([timeless], reads: [ThreadRead(token: "t1", upToMs: nil)]),
      ["a"])
  }

  func testZunosOwnPostsStayWithZuno() {
    let dart = note("dart", token: nil, seconds: nil, appPosted: true, roomId: "!a:x")
    XCTAssertEqual(
      DeliveredSweep.identifiersToRemove(
        [dart], reads: [ThreadRead(token: "t1", roomId: "!a:x", upToMs: nil)]),
      [])
  }

  func testAReadByRoomIdTakesTheStaticAlertsOfThatRoom() {
    let delivered = [
      note("static-a", token: nil, thread: "", seconds: nil, roomId: "!a:x"),
      note("static-b", token: nil, thread: "", seconds: nil, roomId: "!b:x"),
      note("badge", token: nil, thread: "", seconds: nil),
    ]
    XCTAssertEqual(
      DeliveredSweep.identifiersToRemove(delivered, reads: [ThreadRead(roomId: "!a:x")]),
      ["static-a"])
  }

  func testEachReadTakesItsRoomByIdOrByToken() {
    let delivered = [
      note("static-a", token: nil, thread: "", seconds: nil, roomId: "!a:x"),
      note("line-b", token: "tb", thread: "tb"),
      note("line-c", token: "tc", thread: "tc"),
    ]
    XCTAssertEqual(
      DeliveredSweep.identifiersToRemove(
        delivered, reads: [ThreadRead(roomId: "!a:x"), ThreadRead(token: "tb")]),
      ["static-a", "line-b"])
  }

  func testAnEventTimeTooBigToScaleToMillisecondsIsNeverCovered() {
    let removed = DeliveredSweep.identifiersToRemove(
      [note("a", seconds: Int.max)], reads: [ThreadRead(token: "t1", upToMs: 1_790_000_000_000)])
    XCTAssertEqual(removed, [])
  }

  func testAnEmptyTokenOrRoomIdNeverMatches() {
    let removed = DeliveredSweep.identifiersToRemove(
      [note("a", token: nil, thread: "", seconds: 1, roomId: "")],
      reads: [ThreadRead(token: "", upToMs: nil), ThreadRead(roomId: "")])
    XCTAssertEqual(removed, [])
  }

  func testAPushOrACatchUpLineIsPushedWhileTheAppsOwnLocalLineIsNot() throws {
    let pushed = try NseTestData.notification(
      "push-a", userInfo: [:], trigger: NseTestData.pushTrigger())
    let catchUp = try NseTestData.notification("zuno.catchup.e1", userInfo: [:], trigger: nil)
    let own = try NseTestData.notification("42", userInfo: [:], trigger: nil)

    XCTAssertTrue(pushed.isPushed)
    XCTAssertTrue(catchUp.isPushed)
    XCTAssertFalse(own.isPushed)
  }

  func testANoteReadsItsRoomAndEventTimeFromTheNotification() throws {
    let line = try NseTestData.notification(
      "a", userInfo: ["t": "t1", "o": "1790000000", "k": "msg", "room_id": "!a:x"],
      trigger: NseTestData.pushTrigger(), thread: "t1")
    let own = try NseTestData.notification(
      "42", userInfo: ["t": 5, "room_id": 7], trigger: nil, thread: "x")

    XCTAssertEqual(DeliveredNote(line), note("a", seconds: 1_790_000_000, roomId: "!a:x"))
    XCTAssertEqual(
      DeliveredNote(own), note("42", token: nil, thread: "x", seconds: nil, appPosted: true))
  }
}
