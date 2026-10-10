import Foundation

enum NseHttpResult: Equatable, Sendable {
  case response(status: Int, headers: [String: String], body: Data)
  case timeout
  case offline
  case failure
}

protocol NseTransport: Sendable {
  func post(_ url: URL, authorization: String, body: Data, timeoutMs: Int) async -> NseHttpResult
}

protocol NseClock: Sendable {
  func nowMs() -> Int64
  func wait(ms: Int, wakeOn hints: [DarwinHint]) async
}

enum ModuleReply: Equatable, Sendable {
  case reply(status: Int, json: NseJson)
  case route
  case network

  static func of(_ result: NseHttpResult) -> ModuleReply {
    switch result {
    case .timeout, .offline, .failure:
      return .network
    case .response(let status, let headers, let body):
      guard headers["x-zuno-push"] == "1", let json = NseJson.parse(body, "nse module reply parse"),
        json.object != nil
      else { return .route }
      return .reply(status: status, json: json)
    }
  }
}

enum NseModuleUrl {
  static func endpoint(_ baseUrl: String, _ path: String) -> URL? {
    guard let base = URL(string: baseUrl), base.scheme == "https" || base.scheme == "http",
      base.host != nil
    else { return nil }
    return URL(string: "_synapse/client/zuno/push/v1/" + path, relativeTo: base)?.absoluteURL
  }
}

enum NseFetchReply: Equatable, Sendable {
  case ok(NseFetched)
  case read(receiptTs: Int64)
  case gone
  case unauthorized
  case rateLimited
  case route
  case network
  case mismatch
}

struct NseFetchClient: Sendable {
  static let attemptMs = 6000
  static let hardMs = 8000
  static let retryFloorMs = 5000

  let transport: NseTransport
  let clock: NseClock

  func fetch(baseUrl: String, credential: String, roomId: String, eventId: String) async
    -> NseFetchReply
  {
    await fetchWithBody(
      baseUrl: baseUrl, credential: credential, roomId: roomId, eventId: eventId
    ).reply
  }

  func fetchWithBody(baseUrl: String, credential: String, roomId: String, eventId: String)
    async -> (reply: NseFetchReply, body: Data?)
  {
    guard let url = NseModuleUrl.endpoint(baseUrl, "nse/fetch"),
      let body = NseJson.data(["room_id": roomId, "event_id": eventId], "nse fetch body")
    else { return (.route, nil) }
    let start = clock.nowMs()
    var attempt = 0
    while true {
      attempt += 1
      let remaining = Self.hardMs - Int(clock.nowMs() - start)
      guard remaining > 0 else { return (.network, nil) }
      let result = await transport.post(
        url, authorization: "ZunoNotify \(credential)", body: body,
        timeoutMs: min(Self.attemptMs, remaining))
      switch ModuleReply.of(result) {
      case .network:
        let left = Self.hardMs - Int(clock.nowMs() - start)
        if attempt == 1 && left >= Self.retryFloorMs { continue }
        return (.network, nil)
      case .route:
        return (.route, nil)
      case .reply(let status, let json):
        guard case .response(_, _, let data) = result else { return (.route, nil) }
        return (
          Self.interpret(status: status, json: json, roomId: roomId, eventId: eventId),
          status == 200 ? data : nil
        )
      }
    }
  }

  static func interpret(status: Int, json: NseJson, roomId: String, eventId: String)
    -> NseFetchReply
  {
    switch status {
    case 200:
      switch json["status"]?.string {
      case "ok":
        guard let event = NseEvent(json["event"]) else { return .route }
        guard event.roomId == roomId, event.eventId == eventId else { return .mismatch }
        return .ok(
          NseFetched(
            event: event, senderName: json["sender_name"]?.string,
            roomName: json["room_name"]?.string, isDm: json["is_dm"]?.bool ?? false,
            highlight: json["highlight"]?.bool ?? false, serverTs: json["server_ts"]?.int64))
      case "read":
        return .read(receiptTs: json["receipt_ts"]?.int64 ?? 0)
      case "gone":
        return .gone
      default:
        return .route
      }
    case 401:
      return .unauthorized
    case 429:
      return .rateLimited
    default:
      return .route
    }
  }
}
