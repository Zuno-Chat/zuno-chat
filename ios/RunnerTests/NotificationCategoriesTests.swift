import UserNotifications
import XCTest

@testable import Runner

final class NotificationCategoriesTests: XCTestCase {
  private func category(_ identifier: String) throws -> UNNotificationCategory {
    try XCTUnwrap(NotificationCategories.all.first { $0.identifier == identifier })
  }

  func testThereAreExactlyTheMessageAndReplyOnlyCategories() {
    XCTAssertEqual(Set(NotificationCategories.all.map(\.identifier)), ["message", "reply"])
  }

  func testTheMessageCategoryOffersReplyThenMarkAsRead() throws {
    let actions = try category("message").actions
    XCTAssertEqual(actions.map(\.identifier), ["reply", "mark_read"])
    XCTAssertEqual(actions.map(\.title), ["Reply", "Mark as read"])
  }

  func testTheReplyOnlyCategoryOffersOnlyReply() throws {
    XCTAssertEqual(try category("reply").actions.map(\.identifier), ["reply"])
  }

  func testReplyTakesTextAndNeedsTheDeviceUnlocked() throws {
    let reply = try XCTUnwrap(
      try category("message").actions.first as? UNTextInputNotificationAction)
    XCTAssertTrue(reply.options.contains(.authenticationRequired))
    XCTAssertEqual(reply.textInputButtonTitle, "Send")
    XCTAssertEqual(reply.textInputPlaceholder, "Message")
  }

  func testMarkAsReadNeedsNoUnlock() throws {
    let markRead = try XCTUnwrap(try category("message").actions.last)
    XCTAssertEqual(markRead.options, [])
  }

  func testNoActionOpensZunoOrIsDestructive() throws {
    for identifier in ["message", "reply"] {
      for action in try category(identifier).actions {
        XCTAssertFalse(action.options.contains(.foreground), action.identifier)
        XCTAssertFalse(action.options.contains(.destructive), action.identifier)
      }
    }
  }

  func testActionsAttachOnlyToMessagesAtNameAndMessage() {
    XCTAssertEqual(NotificationCategories.identifier(forKind: "msg", level: "full"), "message")
    let without: [(String, String)] = [
      ("msg", "name"), ("msg", "none"), ("msg", ""), ("inv", "full"), ("call", "full"),
      ("sys", "full"), ("", "full"),
    ]
    for (kind, level) in without {
      XCTAssertNil(
        NotificationCategories.identifier(forKind: kind, level: level), "\(kind) \(level)")
    }
  }

  func testLinesShowTheirActionsOnceTheyAreRoutedNatively() {
    XCTAssertTrue(NotificationCategories.nativeActions)
    XCTAssertEqual(NotificationCategories.shown("message"), "message")
    XCTAssertEqual(NotificationCategories.shown(nil), "")
  }
}
