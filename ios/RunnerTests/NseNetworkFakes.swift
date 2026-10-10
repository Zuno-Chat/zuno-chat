import Foundation

@testable import Runner

final class NseFakeClock: NseClock, @unchecked Sendable {
  private let lock = NSLock()
  private var now: Int64
  private var recorded: [String] = []
  private var hook: (@Sendable (Int64) -> Void)?

  init(now: Int64) {
    self.now = now
  }

  var waits: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func onWait(_ hook: @escaping @Sendable (Int64) -> Void) {
    lock.lock()
    self.hook = hook
    lock.unlock()
  }

  func nowMs() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return now
  }

  func advance(_ ms: Int64) {
    lock.lock()
    now += ms
    lock.unlock()
  }

  func wait(ms: Int, wakeOn hints: [DarwinHint]) async {
    let (current, hook) = pass(ms, hints)
    hook?(current)
  }

  private func pass(_ ms: Int, _ hints: [DarwinHint]) -> (Int64, (@Sendable (Int64) -> Void)?) {
    lock.lock()
    defer { lock.unlock() }
    now += Int64(ms)
    recorded.append("\(ms):\(hints.map(\.rawValue).joined(separator: ","))")
    return (now, hook)
  }
}

final class NseFakeTransport: NseTransport, @unchecked Sendable {
  struct Request: Equatable {
    let path: String
    let authorization: String
    let body: NseJson?
    let timeoutMs: Int
  }

  private let lock = NSLock()
  private var scripted: [String: [(NseHttpResult, Int64)]] = [:]
  private var recorded: [Request] = []
  private let clock: NseFakeClock?

  init(clock: NseFakeClock? = nil) {
    self.clock = clock
  }

  var requests: [Request] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func reply(_ path: String, _ result: NseHttpResult, after ms: Int64 = 0) {
    lock.lock()
    scripted[path, default: []].append((result, ms))
    lock.unlock()
  }

  func post(_ url: URL, authorization: String, body: Data, timeoutMs: Int) async
    -> NseHttpResult
  {
    let next = take(url, authorization: authorization, body: body, timeoutMs: timeoutMs)
    clock?.advance(next.1)
    return next.0
  }

  private func take(_ url: URL, authorization: String, body: Data, timeoutMs: Int) -> (
    NseHttpResult, Int64
  ) {
    let path = url.path.components(separatedBy: "/push/v1/").last ?? url.path
    lock.lock()
    defer { lock.unlock() }
    recorded.append(
      Request(
        path: path, authorization: authorization, body: NseJson.parse(body, "test request parse"),
        timeoutMs: timeoutMs))
    var queue = scripted[path] ?? []
    let next = queue.isEmpty ? (NseHttpResult.failure, Int64(0)) : queue.removeFirst()
    scripted[path] = queue
    return next
  }

  static func module(_ status: Int, _ object: [String: Any]) -> NseHttpResult {
    .response(
      status: status, headers: ["x-zuno-push": "1"],
      body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
  }
}

extension NseTestData {
  static func ok(_ event: [String: Any], senderName: String? = "Alice", highlight: Bool = false)
    -> NseHttpResult
  {
    var body: [String: Any] = [
      "status": "ok", "event": event, "room_name": "Design team", "is_dm": false,
      "highlight": highlight, "sound": true, "server_ts": now,
    ]
    if let senderName { body["sender_name"] = senderName }
    return NseFakeTransport.module(200, body)
  }
}
