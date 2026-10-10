import UserNotifications
import XCTest

@testable import Runner

final class NseContentFactoryTests: XCTestCase {
  private func original() -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.body = "New message"
    content.sound = UNNotificationSound(named: UNNotificationSoundName("message_tone.caf"))
    content.userInfo = ["room_id": "!abc:zuno.im", "event_id": "$e", "unread_count": 3]
    return content
  }

  func testADeliveryReplacesTheStaticContentAndItsIds() {
    let delivery = NseComposer.message(
      text: "Lunch?", keepsTextWhenNameOnly: false,
      names: NseNames(title: "Alice", sender: "Alice", isDm: true), level: .full, loud: false,
      tone: true, tokens: NseTokens(t: "t1", e: "e1", o: 5))

    let content = NseContentFactory.content(
      for: NseDelivery(
        title: delivery.title, body: delivery.body, threadId: delivery.threadId,
        userInfo: delivery.userInfo, interruption: delivery.interruption, sound: delivery.sound,
        badge: 4, removals: [], usesOriginal: false),
      original: original())

    XCTAssertEqual(content.title, "Alice")
    XCTAssertEqual(content.body, "Lunch?")
    XCTAssertEqual(content.threadIdentifier, "t1")
    XCTAssertEqual(
      content.userInfo as? [String: String], ["t": "t1", "e": "e1", "o": "5", "k": "msg"])
    XCTAssertEqual(content.interruptionLevel, .passive)
    XCTAssertNil(content.sound)
    XCTAssertEqual(content.badge, 4)
  }

  func testThePassthroughDeliversTheStaticAlertUntouched() {
    let original = original()

    let content = NseContentFactory.content(for: .passthrough, original: original)

    XCTAssertTrue(content === original)
    XCTAssertEqual(content.userInfo["room_id"] as? String, "!abc:zuno.im")
  }

  func testTheCategoryReachesTheNotificationOnlyOnceActionsAreRoutedNatively() {
    var delivery = NseComposer.test()
    delivery.category = "message"
    let content = NseContentFactory.content(for: delivery, original: UNNotificationContent())
    XCTAssertEqual(content.categoryIdentifier, NotificationCategories.shown("message"))
  }

  func testRingsUseTheBundledSounds() {
    XCTAssertNotNil(NseContentFactory.sound(.ring, original: nil))
    XCTAssertNotNil(NseContentFactory.sound(.silentRing, original: nil))
    XCTAssertNil(NseContentFactory.sound(.none, original: nil))
  }

  func testTheSinkDeliversOnceAndFallsBackToTheBestAttempt() {
    let removed = Recorder<[String]>()
    let delivered = Recorder<UNNotificationContent>()
    let sink = NseContentSink(
      original: original(), remove: { removed.add($0) }, handler: { delivered.add($0) })
    var floor = NseDelivery.passthrough
    floor.usesOriginal = false
    floor.title = "Alice"
    floor.body = "New message"
    floor.removals = ["old"]

    sink.offer(floor)
    sink.finish(nil)
    sink.finish(.passthrough)

    XCTAssertEqual(delivered.values.map(\.title), ["Alice"])
    XCTAssertEqual(removed.values, [["old"]])
  }

  func testADeliveredLineKeepsItsTokensTheAppsEventAndWhetherItWasPushed() throws {
    let own = try NseTestData.notification(
      "42",
      userInfo: [
        "t": "ta", "o": "100", "k": "msg", "room_id": "!r:x",
        "payload": #"{"type":"message","roomId":"!r:x","eventId":"$e"}"#,
      ],
      trigger: nil, thread: "ta")
    let pushed = try NseTestData.notification(
      "push-a", userInfo: ["t": "ta"], trigger: NseTestData.pushTrigger())

    let delivered = NseContentFactory.delivered(own)

    XCTAssertEqual(delivered.userInfo, ["t": "ta", "o": "100", "k": "msg"])
    XCTAssertEqual(delivered.threadId, "ta")
    XCTAssertEqual(delivered.payloadEventId, "$e")
    XCTAssertFalse(delivered.pushed)
    XCTAssertTrue(NseContentFactory.delivered(pushed).pushed)
  }
}
