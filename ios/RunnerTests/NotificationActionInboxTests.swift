import XCTest

@testable import Runner

@MainActor
private final class InboxHarness {
  let tasks = FakeBackgroundTasks()
  let timers = FakeTimers()
  var completed: [String] = []
  var notices: [NotificationActionNotice] = []
  var noticeDone: [@MainActor @Sendable () -> Void] = []
  var holdsNotices = false
  var read: [String] = []
  var hints = 0

  private(set) lazy var inbox: NotificationActionInbox = {
    let inbox = NotificationActionInbox(
      begin: { [tasks] in tasks.begin($0, $1) },
      end: { [tasks] in tasks.end($0) },
      schedule: { [timers] in timers.schedule($0, $1) },
      notSent: { [unowned self] notice, done in
        self.notices.append(notice)
        if self.holdsNotices { self.noticeDone.append(done) } else { done() }
      },
      markedRead: { [unowned self] request in self.read.append(request.id) })
    inbox.onAccepted = { [unowned self] in self.hints += 1 }
    return inbox
  }()

  func accept(_ request: NotificationActionRequest) {
    inbox.accept(request) { [weak self] in self?.completed.append(request.id) }
  }
}

private func request(_ id: String, _ kind: NotificationActionKind) -> NotificationActionRequest {
  NotificationActionRequest(
    id: id, kind: kind, roomId: nil, roomToken: "t1", eventId: nil,
    eventSeconds: 1_790_000_000, replyText: kind == .reply ? "on my way" : nil,
    notice: NotificationActionNotice(
      notificationId: "n-\(id)", title: "Maya", thread: "t1", roomId: nil, roomToken: "t1"))
}

@MainActor
final class NotificationActionInboxTests: XCTestCase {
  func testAcceptingAnActionHoldsABackgroundTaskAndArmsTheTimeout() {
    let harness = InboxHarness()
    harness.accept(request("a1", .reply))
    XCTAssertEqual(harness.tasks.events, ["begin zuno:notification_action #1"])
    XCTAssertEqual(harness.timers.pendingDelays, [25_000])
    XCTAssertEqual(harness.inbox.pendingIds, ["a1"])
    XCTAssertTrue(harness.completed.isEmpty)
  }

  func testEachActionIsHandedToDartOnce() {
    let harness = InboxHarness()
    harness.accept(request("a1", .reply))
    harness.accept(request("a2", .markRead))
    XCTAssertEqual(harness.inbox.take().map(\.id), ["a1", "a2"])
    XCTAssertTrue(harness.inbox.take().isEmpty)
    harness.accept(request("a3", .markRead))
    XCTAssertEqual(harness.inbox.take().map(\.id), ["a3"])
  }

  func testAnActionDartFinishedCompletesTheResponseAndEndsItsTask() {
    let harness = InboxHarness()
    harness.accept(request("a1", .reply))
    harness.inbox.finish("a1", ok: true)
    XCTAssertEqual(harness.completed, ["a1"])
    XCTAssertEqual(harness.tasks.running, [])
    XCTAssertEqual(harness.timers.pendingDelays, [])
    XCTAssertTrue(harness.notices.isEmpty)
    XCTAssertTrue(harness.inbox.pendingIds.isEmpty)
  }

  func testMarkAsReadThatWorkedTakesDownTheRoomsNotifications() {
    let harness = InboxHarness()
    harness.accept(request("m1", .markRead))
    harness.inbox.finish("m1", ok: true)
    XCTAssertEqual(harness.read, ["m1"])
    XCTAssertEqual(harness.completed, ["m1"])
  }

  func testAReplyThatFailedIsReportedNotSentBeforeTheResponseCompletes() {
    let harness = InboxHarness()
    harness.holdsNotices = true
    harness.accept(request("a1", .reply))
    harness.inbox.finish("a1", ok: false)
    XCTAssertEqual(harness.notices.map(\.notificationId), ["n-a1"])
    XCTAssertTrue(harness.completed.isEmpty)
    XCTAssertEqual(harness.tasks.running, [1])
    harness.noticeDone.first?()
    XCTAssertEqual(harness.completed, ["a1"])
    XCTAssertEqual(harness.tasks.running, [])
  }

  func testAReplyDartNeverFinishedIsReportedNotSentAtTheTimeout() {
    let harness = InboxHarness()
    harness.accept(request("a1", .reply))
    harness.timers.fire(0)
    XCTAssertEqual(harness.notices.map(\.notificationId), ["n-a1"])
    XCTAssertEqual(harness.completed, ["a1"])
    XCTAssertEqual(harness.tasks.running, [])
    XCTAssertTrue(harness.inbox.pendingIds.isEmpty)
  }

  func testAMarkAsReadDartNeverFinishedOnlyCompletesAtTheTimeout() {
    let harness = InboxHarness()
    harness.accept(request("m1", .markRead))
    harness.timers.fire(0)
    XCTAssertTrue(harness.notices.isEmpty)
    XCTAssertTrue(harness.read.isEmpty)
    XCTAssertEqual(harness.completed, ["m1"])
  }

  func testWhenTheSystemEndsTheTaskItEndsAtOnceAndTheReplyIsStillReported() {
    let harness = InboxHarness()
    harness.holdsNotices = true
    harness.accept(request("a1", .reply))
    harness.tasks.expire(1)
    XCTAssertEqual(harness.tasks.events, ["begin zuno:notification_action #1", "end #1"])
    XCTAssertEqual(harness.notices.count, 1)
    XCTAssertTrue(harness.completed.isEmpty)
    harness.noticeDone.first?()
    XCTAssertEqual(harness.completed, ["a1"])
    XCTAssertEqual(harness.tasks.events, ["begin zuno:notification_action #1", "end #1"])
  }

  func testALateOrRepeatedFinishDoesNothing() {
    let harness = InboxHarness()
    harness.accept(request("a1", .reply))
    harness.timers.fire(0)
    harness.inbox.finish("a1", ok: true)
    harness.inbox.finish("a1", ok: false)
    harness.inbox.finish("unknown", ok: true)
    XCTAssertEqual(harness.completed, ["a1"])
    XCTAssertEqual(harness.notices.count, 1)
    XCTAssertTrue(harness.read.isEmpty)
  }

  func testWithoutABackgroundTaskTheTimeoutStillCompletesTheResponse() {
    let harness = InboxHarness()
    harness.tasks.refuses = true
    harness.accept(request("m1", .markRead))
    harness.timers.fire(0)
    XCTAssertEqual(harness.completed, ["m1"])
    XCTAssertTrue(harness.tasks.events.isEmpty)
  }

  func testEveryAcceptedActionTellsDart() {
    let harness = InboxHarness()
    harness.accept(request("a1", .reply))
    harness.accept(request("a2", .markRead))
    XCTAssertEqual(harness.hints, 2)
  }
}
