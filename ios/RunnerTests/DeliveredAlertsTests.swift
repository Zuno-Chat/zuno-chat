import UserNotifications
import XCTest

@testable import Runner

private final class FakeAlertStore: DeliveredAlertStore, @unchecked Sendable {
  let alerts: [DeliveredAlert]
  private(set) var reads = 0
  private(set) var removed: [[String]] = []

  init(_ alerts: [DeliveredAlert]) {
    self.alerts = alerts
  }

  func delivered() async -> [DeliveredAlert] {
    reads += 1
    return alerts
  }

  func remove(_ identifiers: [String]) {
    removed.append(identifiers)
  }
}

final class DeliveredAlertsTests: XCTestCase {
  private let alerts = [
    DeliveredAlert(identifier: "push-a1", pushed: true, roomId: "!a:example.org"),
    DeliveredAlert(identifier: "local-a", pushed: false, roomId: "!a:example.org"),
    DeliveredAlert(identifier: "push-b", pushed: true, roomId: "!b:example.org"),
    DeliveredAlert(identifier: "push-a2", pushed: true, roomId: "!a:example.org"),
    DeliveredAlert(identifier: "push-badge", pushed: true, roomId: nil),
  ]

  private let tokenAlerts = [
    DeliveredAlert(identifier: "rewritten-a", pushed: true, roomId: nil, roomToken: "ta"),
    DeliveredAlert(identifier: "static-a", pushed: true, roomId: "!a:example.org"),
    DeliveredAlert(identifier: "rewritten-b", pushed: true, roomId: nil, roomToken: "tb"),
    DeliveredAlert(identifier: "local-a", pushed: false, roomId: nil, roomToken: "ta"),
  ]

  func testEveryAlertApplePushedForAReadRoomGoes() {
    XCTAssertEqual(
      DeliveredAlerts.identifiers(of: alerts, inRooms: ["!a:example.org"]), ["push-a1", "push-a2"])
  }

  func testTheAppsOwnNotificationsAreLeftToTheApp() {
    XCTAssertFalse(
      DeliveredAlerts.identifiers(of: alerts, inRooms: ["!a:example.org"]).contains("local-a"))
  }

  func testAlertsOfUnreadRoomsAndAlertsWithoutARoomStay() {
    XCTAssertEqual(DeliveredAlerts.identifiers(of: alerts, inRooms: ["!c:example.org"]), [])
    XCTAssertEqual(DeliveredAlerts.identifiers(of: alerts, inRooms: []), [])
  }

  func testSeveralReadRoomsGoTogether() {
    XCTAssertEqual(
      DeliveredAlerts.identifiers(of: alerts, inRooms: ["!a:example.org", "!b:example.org"]),
      ["push-a1", "push-b", "push-a2"])
  }

  func testRemovingForReadRoomsTakesTheirAlertsDownInOneCall() async {
    let store = FakeAlertStore(alerts)

    let removed = await DeliveredAlerts.remove(inRooms: ["!a:example.org"], from: store)

    XCTAssertEqual(removed, 2)
    XCTAssertEqual(store.removed, [["push-a1", "push-a2"]])
  }

  func testNothingDeliveredForTheReadRoomsRemovesNothing() async {
    let store = FakeAlertStore(alerts)

    let removed = await DeliveredAlerts.remove(inRooms: ["!c:example.org"], from: store)

    XCTAssertEqual(removed, 0)
    XCTAssertEqual(store.removed, [])
  }

  func testNoReadRoomsAsksNothingOfTheSystem() async {
    let store = FakeAlertStore(alerts)

    let removed = await DeliveredAlerts.remove(inRooms: [], from: store)

    XCTAssertEqual(removed, 0)
    XCTAssertEqual(store.reads, 0)
  }

  func testAReadRoomTakesDownTheExtensionsLinesByToken() {
    XCTAssertEqual(
      DeliveredAlerts.identifiers(of: tokenAlerts, inRooms: ["!a:example.org"], tokens: ["ta"]),
      ["rewritten-a", "static-a"])
  }

  func testWithoutTokensOnlyStaticAlertsGo() {
    XCTAssertEqual(
      DeliveredAlerts.identifiers(of: tokenAlerts, inRooms: ["!a:example.org"]), ["static-a"])
  }

  func testTheAppsOwnLinesWithATokenStayWithTheApp() async {
    let store = FakeAlertStore(tokenAlerts)

    let removed = await DeliveredAlerts.remove(
      inRooms: ["!b:example.org"], tokens: ["tb", "ta"], from: store)

    XCTAssertEqual(removed, 2)
    XCTAssertEqual(store.removed, [["rewritten-a", "rewritten-b"]])
  }
}

@MainActor
extension DeliveredAlertsTests {
  private func unknownRoom() -> String {
    "!\(UUID().uuidString):example.org"
  }

  private func removeDelivered(
    _ arguments: Any?, from store: (any DeliveredAlertStore)? = nil
  ) async -> (answer: Any?, onMainThread: Bool) {
    let plugin = store.map { ApnsTokenPlugin(alerts: $0) } ?? ApnsTokenPlugin()
    return await channelReply(from: plugin, method: "removeDelivered", arguments: arguments)
  }

  private func pushTrigger() throws -> UNNotificationTrigger {
    let seed = try NSKeyedArchiver.archivedData(
      withRootObject: NSDictionary(), requiringSecureCoding: false)
    let coder = try NSKeyedUnarchiver(forReadingFrom: seed)
    coder.requiresSecureCoding = false
    return try XCTUnwrap(UNPushNotificationTrigger(coder: coder))
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

  func testTheRealNotificationCenterReadsAndRemovesWithoutTrapping() async {
    await runWithinSystemTimeout {
      let center = SystemDeliveredAlerts()
      _ = await center.delivered()
      center.remove([UUID().uuidString])
    }
  }

  func testAnUnknownRoomRemovesNothingFromTheRealNotificationCenter() async {
    let room = unknownRoom()
    await runWithinSystemTimeout {
      let removed = await DeliveredAlerts.remove(inRooms: [room])
      XCTAssertEqual(removed, 0)
    }
  }

  func testTheChannelAnswersTheRemovedCountAsAnIntOnTheMainThread() async {
    let reply = await removeDelivered(["roomIds": [unknownRoom(), unknownRoom()]])

    XCTAssertEqual(reply.answer as? Int, 0)
    XCTAssertTrue(reply.onMainThread)
  }

  func testAPluginBuiltWithoutAStoreUsesTheRealNotificationCenter() {
    let stores = Mirror(reflecting: ApnsTokenPlugin()).children.compactMap {
      $0.value as? SystemDeliveredAlerts
    }

    XCTAssertEqual(stores.count, 1)
  }

  func testTheChannelTakesDownTheAlertsOfAReadRoomAndAnswersTheirCount() async {
    let store = FakeAlertStore(alerts)

    let reply = await removeDelivered(["roomIds": ["!a:example.org"]], from: store)

    XCTAssertEqual(reply.answer as? Int, 2)
    XCTAssertTrue(reply.onMainThread)
    XCTAssertEqual(store.removed, [["push-a1", "push-a2"]])
  }

  func testTheChannelTakesDownSeveralReadRoomsTogether() async {
    let store = FakeAlertStore(alerts)

    let reply = await removeDelivered(
      ["roomIds": ["!a:example.org", "!b:example.org"]], from: store)

    XCTAssertEqual(reply.answer as? Int, 3)
    XCTAssertEqual(store.removed, [["push-a1", "push-b", "push-a2"]])
  }

  func testTheChannelRemovesNothingForMissingOrMalformedRoomIds() async {
    let malformed: [Any?] = [
      nil, "roomIds", [String: Any](), ["other": ["!a:example.org"]],
      ["roomIds": []], ["roomIds": "!a:example.org"], ["roomIds": [1, 2]],
      ["roomIds": ["!a:example.org", 5] as [Any]],
    ]
    for arguments in malformed {
      let store = FakeAlertStore(alerts)
      let label = String(describing: arguments)

      let reply = await removeDelivered(arguments, from: store)

      XCTAssertEqual(reply.answer as? Int, 0, label)
      XCTAssertTrue(reply.onMainThread, label)
      XCTAssertEqual(store.removed, [], label)
      XCTAssertEqual(store.reads, 0, label)
    }
  }

  func testAPushedNotificationIsReadAsPushedWithItsRoom() throws {
    let payload: [AnyHashable: Any] = [
      "aps": ["alert": "New message"], "room_id": "!a:example.org", "event_id": "$e",
    ]
    let pushed = try notification("push-a", userInfo: payload, trigger: pushTrigger())

    XCTAssertEqual(
      DeliveredAlert(pushed),
      DeliveredAlert(identifier: "push-a", pushed: true, roomId: "!a:example.org"))
  }

  func testANotificationWithoutAPushTriggerIsReadAsNotPushedAndStaysWithTheApp() throws {
    let payload: [AnyHashable: Any] = ["room_id": "!a:example.org"]
    let pushed = try notification("push-a", userInfo: payload, trigger: pushTrigger())
    let local = try notification("local-a", userInfo: payload, trigger: nil)

    XCTAssertEqual(
      DeliveredAlert(local),
      DeliveredAlert(identifier: "local-a", pushed: false, roomId: "!a:example.org"))
    XCTAssertEqual(
      DeliveredAlerts.identifiers(
        of: [DeliveredAlert(pushed), DeliveredAlert(local)], inRooms: ["!a:example.org"]),
      ["push-a"])
  }

  func testACatchUpLineGoesWithItsRoomWhileTheAppsOwnLineWithTheSameTokenStays() throws {
    let info: [AnyHashable: Any] = ["t": "ta", "e": "e1", "o": "100", "k": "msg"]
    let catchUp = try notification("zuno.catchup.e1", userInfo: info, trigger: nil)
    let own = try notification("42", userInfo: info, trigger: nil)
    XCTAssertEqual(
      DeliveredAlerts.identifiers(
        of: [DeliveredAlert(catchUp), DeliveredAlert(own)], inRooms: [], tokens: ["ta"]),
      ["zuno.catchup.e1"])
  }

  func testAPushWithoutAStringRoomIdIsReadWithNoRoom() throws {
    let badge = try notification(
      "push-badge", userInfo: ["aps": ["badge": 1]], trigger: pushTrigger())
    let numeric = try notification(
      "push-number", userInfo: ["room_id": 5], trigger: pushTrigger())

    XCTAssertEqual(
      DeliveredAlert(badge), DeliveredAlert(identifier: "push-badge", pushed: true, roomId: nil))
    XCTAssertEqual(
      DeliveredAlert(numeric), DeliveredAlert(identifier: "push-number", pushed: true, roomId: nil))
  }

  func testAnExtensionRewrittenPushIsReadWithItsRoomToken() throws {
    let rewritten = try notification(
      "rewritten-a", userInfo: ["aps": ["alert": "New message"], "t": "ta"],
      trigger: pushTrigger())
    let numeric = try notification("rewritten-n", userInfo: ["t": 5], trigger: pushTrigger())

    XCTAssertEqual(
      DeliveredAlert(rewritten),
      DeliveredAlert(identifier: "rewritten-a", pushed: true, roomId: nil, roomToken: "ta"))
    XCTAssertEqual(
      DeliveredAlert(numeric),
      DeliveredAlert(identifier: "rewritten-n", pushed: true, roomId: nil, roomToken: nil))
  }
}
