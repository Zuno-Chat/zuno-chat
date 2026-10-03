import XCTest

@testable import Runner

final class NseFetchClientTests: XCTestCase {
  private let clock = NseFakeClock(now: NseTestData.now)
  private lazy var transport = NseFakeTransport(clock: clock)
  private lazy var client = NseFetchClient(transport: transport, clock: clock)

  private func fetch(baseUrl: String = "https://zuno.im") async -> NseFetchReply {
    await client.fetch(
      baseUrl: baseUrl, credential: "cred", roomId: NseTestData.roomId,
      eventId: NseTestData.eventId)
  }

  func testAnOkReplyCarriesTheEventAndNames() async {
    transport.reply(
      "nse/fetch", NseTestData.ok(NseTestData.event(content: ["msgtype": "m.text", "body": "hi"])))

    guard case .ok(let fetched) = await fetch() else { return XCTFail("not ok") }
    XCTAssertEqual(fetched.event.content["body"], .string("hi"))
    XCTAssertEqual(fetched.senderName, "Alice")
    XCTAssertEqual(fetched.roomName, "Design team")
    XCTAssertEqual(
      transport.requests,
      [
        .init(
          path: "nse/fetch", authorization: "ZunoNotify cred",
          body: .object([
            "room_id": .string(NseTestData.roomId), "event_id": .string(NseTestData.eventId),
          ]), timeoutMs: 6000)
      ])
  }

  func testModuleRepliesMapToTheirOutcomes() async {
    let cases: [(NseHttpResult, NseFetchReply)] = [
      (NseFakeTransport.module(200, ["status": "read", "receipt_ts": 7]), .read(receiptTs: 7)),
      (NseFakeTransport.module(200, ["status": "gone"]), .gone),
      (NseFakeTransport.module(401, ["errcode": "IM.ZUNO.BAD_CREDENTIAL"]), .unauthorized),
      (
        NseFakeTransport.module(429, ["errcode": "M_LIMIT_EXCEEDED", "retry_after_ms": 5]),
        .rateLimited
      ),
      (NseFakeTransport.module(503, ["errcode": "IM.ZUNO.PUSH_DISABLED"]), .route),
      (NseFakeTransport.module(503, ["errcode": "IM.ZUNO.STARTING"]), .route),
      (NseFakeTransport.module(200, ["status": "maybe"]), .route),
    ]
    for (reply, expected) in cases {
      transport.reply("nse/fetch", reply)
      let actual = await fetch()
      XCTAssertEqual(actual, expected)
    }
  }

  func testAReplyWithoutTheModuleHeaderIsARouteFailure() async {
    let synapse404 = NseHttpResult.response(
      status: 404, headers: [:], body: Data(#"{"errcode":"M_UNRECOGNIZED"}"#.utf8))
    let proxyPage = NseHttpResult.response(
      status: 200, headers: ["x-zuno-push": "1"], body: Data("<html>".utf8))
    transport.reply("nse/fetch", synapse404)
    transport.reply("nse/fetch", proxyPage)

    let first = await fetch()
    let second = await fetch()
    XCTAssertEqual(first, .route)
    XCTAssertEqual(second, .route)
  }

  func testAnEventForAnotherRoomIsAMismatch() async {
    var event = NseTestData.event(content: ["body": "hi"])
    event["room_id"] = "!other:zuno.im"
    transport.reply("nse/fetch", NseTestData.ok(event))

    let reply = await fetch()
    XCTAssertEqual(reply, .mismatch)
  }

  func testAFastNetworkFailureIsRetriedOnceWithinEightSeconds() async {
    transport.reply("nse/fetch", .offline, after: 1000)
    transport.reply("nse/fetch", .offline, after: 1000)

    let reply = await fetch()
    XCTAssertEqual(reply, .network)
    XCTAssertEqual(transport.requests.map(\.timeoutMs), [6000, 6000])
  }

  func testATimeoutLeavesTooLittleTimeForARetry() async {
    transport.reply("nse/fetch", .timeout, after: 6000)

    let reply = await fetch()
    XCTAssertEqual(reply, .network)
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testTheModulePathFollowsTheHomeserverBaseUrl() {
    XCTAssertEqual(
      NseModuleUrl.endpoint("https://zuno.im/base/", "nse/fetch")?.absoluteString,
      "https://zuno.im/base/_synapse/client/zuno/push/v1/nse/fetch")
    XCTAssertEqual(
      NseModuleUrl.endpoint("https://zuno.im", "ring/status")?.absoluteString,
      "https://zuno.im/_synapse/client/zuno/push/v1/ring/status")
    XCTAssertEqual(
      NseModuleUrl.endpoint("https://zuno.im/base", "nse/fetch")?.absoluteString,
      "https://zuno.im/_synapse/client/zuno/push/v1/nse/fetch")
    XCTAssertNil(NseModuleUrl.endpoint("ftp://zuno.im", "nse/fetch"))
    XCTAssertNil(NseModuleUrl.endpoint("not a url", "nse/fetch"))
  }

  private func ringReply(
    _ status: String, sentTs: Int64? = nil, rule: String? = nil
  ) -> NseHttpResult {
    NseFakeTransport.module(
      200,
      [
        "status": status, "sent_ts": sentTs.map { $0 as Any } ?? NSNull(),
        "rule": rule.map { $0 as Any } ?? NSNull(), "server_ts": 10,
      ])
  }

  func testRingStatusRepliesMapToTheirStatuses() async {
    let ring = RingStatusClient(transport: transport)
    let cases: [(NseHttpResult, NseRingStatus)] = [
      (ringReply("sent", sentTs: 9), .sent(sentTs: 9)),
      (ringReply("sent"), .sent(sentTs: nil)),
      (ringReply("suppressed", rule: "not_allowed"), .suppressed(rule: "not_allowed")),
      (ringReply("suppressed"), .suppressed(rule: nil)),
      (ringReply("no_token", rule: "voip_failing"), .noToken),
      (ringReply("failed"), .failed),
      (ringReply("pending"), .pending),
      (ringReply("queued"), .unknown),
      (NseFakeTransport.module(503, ["errcode": "IM.ZUNO.STARTING"]), .unknown),
      (NseFakeTransport.module(500, ["errcode": "M_UNKNOWN"]), .unknown),
      (.response(status: 404, headers: [:], body: Data()), .unknown),
      (.timeout, .unknown),
    ]
    for (reply, expected) in cases {
      transport.reply("ring/status", reply)
      let actual = await ring.status(
        baseUrl: "https://zuno.im", credential: "cred", roomId: "!r", callId: "c", waitMs: 4000)
      XCTAssertEqual(actual.status, expected)
    }
  }

  func testRingStatusWaitsAtMostTenSecondsPlusSlack() async {
    let ring = RingStatusClient(transport: transport)
    transport.reply("ring/status", NseFakeTransport.module(200, ["status": "pending"]))

    _ = await ring.status(
      baseUrl: "https://zuno.im", credential: "cred", roomId: "!r", callId: "c", waitMs: 30_000)

    XCTAssertEqual(transport.requests.first?.body?["wait_ms"]?.int64, 10_000)
    XCTAssertEqual(transport.requests.first?.timeoutMs, 12_000)
  }
}
