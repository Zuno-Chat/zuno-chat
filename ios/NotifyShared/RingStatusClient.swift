import Foundation

enum NseRingStatus: Equatable, Sendable {
  case sent(sentTs: Int64?)
  case suppressed(rule: String?)
  case failed
  case noToken
  case pending
  case unknown
}

struct RingStatusReply: Equatable, Sendable {
  let status: NseRingStatus
  let serverTs: Int64?
}

struct RingStatusClient: Sendable {
  static let maxWaitMs = 10_000
  static let slackMs = 2000
  static let voipFailingRule = "voip_failing"

  let transport: NseTransport

  func status(baseUrl: String, credential: String, roomId: String, callId: String, waitMs: Int)
    async -> RingStatusReply
  {
    let wait = max(0, min(Self.maxWaitMs, waitMs))
    guard let url = NseModuleUrl.endpoint(baseUrl, "ring/status"),
      let body = NseJson.data(
        ["room_id": roomId, "call_id": callId, "wait_ms": wait], "ring status body")
    else { return RingStatusReply(status: .unknown, serverTs: nil) }
    let result = await transport.post(
      url, authorization: "ZunoNotify \(credential)", body: body, timeoutMs: wait + Self.slackMs)
    guard case .reply(200, let json) = ModuleReply.of(result) else {
      return RingStatusReply(status: .unknown, serverTs: nil)
    }
    let status: NseRingStatus
    switch json["status"]?.string {
    case "sent": status = .sent(sentTs: json["sent_ts"]?.int64)
    case "suppressed": status = .suppressed(rule: json["rule"]?.string)
    case "failed": status = .failed
    case "no_token": status = .noToken
    case "pending": status = .pending
    default: status = .unknown
    }
    return RingStatusReply(status: status, serverTs: json["server_ts"]?.int64)
  }
}
