import XCTest

@testable import Runner

private final class FakeAlertStore: DeliveredAlertStore, @unchecked Sendable {
  let alerts: [DeliveredNote]
  private(set) var reads = 0
  private(set) var removed: [[String]] = []

  init(_ alerts: [DeliveredNote]) {
    self.alerts = alerts
  }

  func delivered() async -> [DeliveredNote] {
    reads += 1
    return alerts
  }

  func remove(_ identifiers: [String]) {
    removed.append(identifiers)
  }
}

private func alert(
  _ identifier: String, roomId: String? = nil, token: String? = nil, pushed: Bool = true
) -> DeliveredNote {
  DeliveredNote(
    identifier: identifier, thread: token ?? "", roomToken: token, seconds: nil,
    appPosted: !pushed, roomId: roomId)
}

final class DeliveredAlertsTests: XCTestCase {
  private let alerts = [
    alert("push-a1", roomId: "!a:example.org"),
    alert("local-a", roomId: "!a:example.org", pushed: false),
    alert("push-b", roomId: "!b:example.org"),
    alert("push-a2", roomId: "!a:example.org"),
    alert("push-badge"),
  ]

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

    let removed = await DeliveredAlerts.remove(inRooms: [], tokens: ["ta"], from: store)

    XCTAssertEqual(removed, 0)
    XCTAssertEqual(store.reads, 0)
  }

  func testAReadRoomAlsoTakesDownTheExtensionsLinesByToken() async {
    let store = FakeAlertStore([
      alert("rewritten-a", token: "ta"),
      alert("static-a", roomId: "!a:example.org"),
      alert("rewritten-b", token: "tb"),
    ])

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

  func testTheRealNotificationCenterReadsAndRemovesWithoutTrapping() async {
    await runWithinSystemTimeout {
      let center = SystemDeliveredAlerts()
      _ = await center.delivered()
      center.remove([UUID().uuidString])
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
}
