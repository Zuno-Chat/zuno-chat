import Security
import UserNotifications
import XCTest

@testable import Runner

@MainActor
private final class CommandHarness {
  var completed: [String] = []
  let inbox = NotificationActionInbox(
    begin: { _, _ in nil }, end: { _ in }, schedule: { _, _ in {} },
    notSent: { _, done in done() }, markedRead: { _ in })

  func accept(_ id: String) {
    let request = NotificationActionRequest(
      id: id, kind: .markRead, roomId: "!r:x", roomToken: nil, eventId: "$e",
      eventSeconds: nil, replyText: nil,
      notice: NotificationActionNotice(
        notificationId: "n", title: "Maya", thread: "!r:x", roomId: "!r:x", roomToken: nil))
    inbox.accept(request) { [weak self] in self?.completed.append(id) }
  }
}

@MainActor
final class NotificationActionsCommandTests: XCTestCase {
  func testTakingActionsHandsTheirChannelValuesOnce() {
    let harness = CommandHarness()
    harness.accept("a1")
    guard
      case .actions(let first) = NotificationActionsCommand.handle(
        "takeActions", nil, inbox: harness.inbox)
    else { return XCTFail("takeActions did not answer actions") }
    XCTAssertEqual(first.map { $0["id"] as? String }, ["a1"])
    guard
      case .actions(let second) = NotificationActionsCommand.handle(
        "takeActions", nil, inbox: harness.inbox)
    else { return XCTFail("takeActions did not answer actions") }
    XCTAssertTrue(second.isEmpty)
  }

  func testFinishingAnActionCompletesItsResponse() {
    let harness = CommandHarness()
    harness.accept("a1")
    guard
      case .done = NotificationActionsCommand.handle(
        "finish", ["id": "a1", "ok": true], inbox: harness.inbox)
    else { return XCTFail("finish did not answer done") }
    XCTAssertEqual(harness.completed, ["a1"])
  }

  func testAFinishWithoutAnIdIsRefused() {
    let harness = CommandHarness()
    harness.accept("a1")
    let refused: [Any?] = [
      nil, ["ok": true] as [String: Any], ["id": "", "ok": true] as [String: Any],
      ["id": 7] as [String: Any],
    ]
    for arguments in refused {
      guard
        case .badArguments = NotificationActionsCommand.handle(
          "finish", arguments, inbox: harness.inbox)
      else { return XCTFail("\(String(describing: arguments)) was accepted") }
    }
    XCTAssertTrue(harness.completed.isEmpty)
  }

  func testOtherMethodsAreNotImplemented() {
    guard
      case .notImplemented = NotificationActionsCommand.handle(
        "openRoom", nil, inbox: CommandHarness().inbox)
    else { return XCTFail("openRoom was handled") }
  }
}

final class FirstUnlockProbeTests: XCTestCase {
  func testAKeychainThatWillNotOpenMeansTheDeviceWasNotUnlockedSinceItStarted() {
    XCTAssertFalse(FirstUnlockProbe.passed(status: errSecInteractionNotAllowed))
    XCTAssertFalse(FirstUnlockProbe.passed(status: errSecNotAvailable))
  }

  func testAnyOtherAnswerLetsTheActionRun() {
    for status in [
      errSecSuccess, errSecItemNotFound, errSecMissingEntitlement, errSecDuplicateItem,
    ] {
      XCTAssertTrue(FirstUnlockProbe.passed(status: status), "\(status)")
    }
  }
}

final class MarkReadTakeDownTests: XCTestCase {
  private let delivered = [
    DeliveredNote(identifier: "acted", thread: "ta", roomToken: "ta", seconds: 100),
    DeliveredNote(identifier: "older", thread: "ta", roomToken: "ta", seconds: 90),
    DeliveredNote(identifier: "newer", thread: "ta", roomToken: "ta", seconds: 300),
    DeliveredNote(identifier: "zuno.catchup.e9", thread: "ta", roomToken: "ta", seconds: 400),
    DeliveredNote(identifier: "other", thread: "tb", roomToken: "tb", seconds: 50),
    DeliveredNote(
      identifier: "own", thread: "ta", roomToken: "ta", seconds: 20, appPosted: true),
  ]

  private func request(eventSeconds: Int?) -> NotificationActionRequest {
    NotificationActionRequest(
      id: "a1", kind: .markRead, roomId: nil, roomToken: "ta", eventId: nil,
      eventSeconds: eventSeconds, replyText: nil,
      notice: NotificationActionNotice(
        notificationId: "acted", title: "Maya", thread: "ta", roomId: nil, roomToken: "ta"))
  }

  func testMarkingAsReadTakesDownTheRoomsLinesUpToTheNotifiedEvent() {
    let identifiers = NotificationActionEffects.identifiersToTakeDown(
      request(eventSeconds: 100), delivered: delivered)

    XCTAssertEqual(Set(identifiers), ["acted", "older"])
  }

  func testMarkingAsReadWithoutAnEventTimeTakesDownOnlyTheNotificationActedOn() {
    let identifiers = NotificationActionEffects.identifiersToTakeDown(
      request(eventSeconds: nil), delivered: delivered)

    XCTAssertEqual(identifiers, ["acted"])
  }
}

final class ReplyNotSentForActionTests: XCTestCase {
  private let token = "2d2de6b6c6565ad95bf365845db19da9"

  private func notice(
    roomId: String? = nil, roomToken: String? = nil, thread: String = ""
  ) -> NotificationActionNotice {
    NotificationActionNotice(
      notificationId: "n1", title: "Maya", thread: thread, roomId: roomId, roomToken: roomToken)
  }

  func testTheNoticeKeepsTheConversationTitleAndThread() {
    let request = ReplyNotSentNotice.request(for: notice(roomToken: token, thread: token))
    XCTAssertEqual(request.content.title, "Maya")
    XCTAssertEqual(request.content.threadIdentifier, token)
  }

  func testTheNoticeSaysWhatHappenedAndWhatToDo() {
    XCTAssertEqual(
      ReplyNotSentNotice.request(for: notice()).content.body,
      "Message not sent. Open Zuno and send it again.")
  }

  func testANoticeForAnExtensionNotificationCarriesOnlyTheOpaqueRoomToken() {
    let request = ReplyNotSentNotice.request(for: notice(roomToken: token, thread: token))
    XCTAssertEqual(request.content.userInfo["t"] as? String, token)
    XCTAssertNil(request.content.userInfo["k"])
    XCTAssertNil(request.content.userInfo["room_id"])
  }

  func testTheNoticeKeepsNoRoomInTheBadge() {
    let request = ReplyNotSentNotice.request(for: notice(roomToken: token, thread: token))

    XCTAssertEqual(
      NseComposer.badge(
        unread: [], delivered: [NseTestData.delivered(request)], removed: [], current: nil), 0)
  }

  func testTappingTheNoticeOpensItsRoom() {
    let posted = ReplyNotSentNotice.request(for: notice(roomId: "!r:x", thread: "!r:x"))
    XCTAssertEqual(NotificationResponseRoute.roomId(in: posted.content.userInfo), "!r:x")
    let token = self.token
    let pushed = ReplyNotSentNotice.request(for: notice(roomToken: token, thread: token))
    XCTAssertEqual(
      NotificationResponseRoute.roomId(
        in: pushed.content.userInfo, resolveToken: { $0 == token ? "!r:x" : nil }),
      "!r:x")
  }

  func testANewNoticeForTheSameRoomReplacesTheLastOne() {
    let first = ReplyNotSentNotice.request(for: notice(roomToken: token))
    let again = ReplyNotSentNotice.request(for: notice(roomToken: token))
    let other = ReplyNotSentNotice.request(for: notice(roomId: "!b:x"))
    XCTAssertEqual(first.identifier, again.identifier)
    XCTAssertNotEqual(first.identifier, other.identifier)
  }

  func testANoticeWithoutARoomStandsAloneAndOpensNothing() {
    let first = ReplyNotSentNotice.request(for: notice())
    let second = ReplyNotSentNotice.request(for: notice())
    XCTAssertNotEqual(first.identifier, second.identifier)
    XCTAssertTrue(first.content.userInfo.isEmpty)
  }

  func testTheNoticeArrivesAtOnceWithoutSoundOrActions() {
    let request = ReplyNotSentNotice.request(for: notice(roomId: "!a:x"))
    XCTAssertNil(request.trigger)
    XCTAssertNil(request.content.sound)
    XCTAssertEqual(request.content.categoryIdentifier, "")
  }
}
