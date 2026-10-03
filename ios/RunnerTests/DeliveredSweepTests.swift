import XCTest

@testable import Runner

final class DeliveredSweepTests: XCTestCase {
  private func note(
    _ identifier: String, token: String? = "t1", thread: String = "t1", seconds: Int? = 100
  ) -> DeliveredNote {
    DeliveredNote(identifier: identifier, thread: thread, roomToken: token, seconds: seconds)
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
    let dart = DeliveredNote(
      identifier: "dart", thread: "t1", roomToken: nil, seconds: nil, appPosted: true)
    XCTAssertEqual(
      DeliveredSweep.identifiersToRemove([dart], reads: [ThreadRead(token: "t1", upToMs: nil)]),
      [])
  }

  func testOnlyLocalPostsThatAreNotCatchUpLinesAreZunosOwn() {
    let info: [AnyHashable: Any] = ["t": "t1", "o": "100", "k": "msg"]
    XCTAssertFalse(DeliveredNote(identifier: "p", thread: "t1", userInfo: info).appPosted)
    XCTAssertFalse(
      DeliveredNote(identifier: "zuno.catchup.e1", thread: "t1", userInfo: info, pushed: false)
        .appPosted)
    XCTAssertTrue(
      DeliveredNote(identifier: "42", thread: "t1", userInfo: [:], pushed: false).appPosted)
  }

  func testAnEventTimeTooBigToScaleToMillisecondsIsNeverCovered() {
    let removed = DeliveredSweep.identifiersToRemove(
      [note("a", seconds: Int.max)], reads: [ThreadRead(token: "t1", upToMs: 1_790_000_000_000)])
    XCTAssertEqual(removed, [])
  }

  func testAnEmptyTokenNeverMatches() {
    let removed = DeliveredSweep.identifiersToRemove(
      [note("a", token: nil, thread: "", seconds: 1)], reads: [ThreadRead(token: "", upToMs: nil)])
    XCTAssertEqual(removed, [])
  }

  func testTheTokenAndEventTimeAreReadFromUserInfo() {
    let read = DeliveredNote(
      identifier: "a", thread: "t1",
      userInfo: ["t": "t1", "o": NSNumber(value: 1_790_000_000), "k": "msg"])
    XCTAssertEqual(read, note("a", seconds: 1_790_000_000))
    let composed = DeliveredNote(
      identifier: "a", thread: "t1", userInfo: ["t": "t1", "o": "1790000000", "k": "msg"])
    XCTAssertEqual(composed, note("a", seconds: 1_790_000_000))
    let odd = DeliveredNote(identifier: "b", thread: "x", userInfo: ["t": 5, "o": "soon"])
    XCTAssertNil(odd.roomToken)
    XCTAssertNil(odd.seconds)
  }
}
