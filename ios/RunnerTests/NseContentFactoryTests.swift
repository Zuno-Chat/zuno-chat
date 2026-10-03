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

  func testRingsUseTheBundledSounds() {
    XCTAssertNotNil(NseContentFactory.sound(.ring, original: nil))
    XCTAssertNotNil(NseContentFactory.sound(.silentRing, original: nil))
    XCTAssertNil(NseContentFactory.sound(.none, original: nil))
  }

  func testTheSinkDeliversOnceAndFallsBackToTheBestAttempt() {
    let removed = NseRecorder<[String]>()
    let delivered = NseRecorder<UNNotificationContent>()
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

  func testACatchUpLineIsReadAsPushedWhileTheAppsOwnLocalLineIsNot() throws {
    let info: [AnyHashable: Any] = ["t": "ta", "e": "e1", "o": "100", "k": "msg"]
    let catchUp = try notification("zuno.catchup.e1", userInfo: info, trigger: nil)
    let own = try notification("42", userInfo: info, trigger: nil)

    XCTAssertTrue(NseContentFactory.delivered(catchUp).pushed)
    XCTAssertFalse(NseContentFactory.delivered(own).pushed)
  }

  private func notification(
    _ identifier: String, userInfo: [AnyHashable: Any], trigger: UNNotificationTrigger?
  ) throws -> UNNotification {
    let content = UNMutableNotificationContent()
    content.userInfo = userInfo
    let archiver = NSKeyedArchiver(requiringSecureCoding: false)
    archiver.encode(
      UNNotificationRequest(identifier: identifier, content: content, trigger: trigger),
      forKey: "request")
    archiver.encode(Date(), forKey: "date")
    archiver.finishEncoding()
    let coder = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
    coder.requiresSecureCoding = false
    return try XCTUnwrap(UNNotification(coder: coder))
  }
}

final class NseRecorder<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Value] = []

  var values: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func add(_ value: Value) {
    lock.lock()
    recorded.append(value)
    lock.unlock()
  }
}
