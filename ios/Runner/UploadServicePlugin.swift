@preconcurrency import Flutter
import UIKit
import os

@MainActor
final class UploadServicePlugin: NSObject, @preconcurrency FlutterPlugin {
  private var task: UIBackgroundTaskIdentifier = .invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/upload_service", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(UploadServicePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      endTask()
      task = UIApplication.shared.beginBackgroundTask(withName: "Upload") { [weak self] in
        MainActor.assumeIsolated { self?.endTask() }
      }
      result(nil)
    case "update":
      result(nil)
    case "stop":
      endTask()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func endTask() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}

@MainActor
enum MainActorTimer {
  static func schedule(
    _ milliseconds: Int, _ fire: @escaping @MainActor @Sendable () -> Void
  ) -> @MainActor () -> Void {
    let delay = UInt64(min(max(milliseconds, 0), 86_400_000)) * NSEC_PER_MSEC
    let timer = Task { @MainActor in
      try? await Task.sleep(nanoseconds: delay)
      guard !Task.isCancelled else { return }
      fire()
    }
    return { timer.cancel() }
  }
}

@MainActor
final class WakeLockPlugin: NSObject, @preconcurrency FlutterPlugin {
  private enum Channel: String, CaseIterable {
    case wakeLock = "zuno/wake_lock"
    case pushWakeLock = "zuno/push_wakelock"
  }

  private static let defaultTag = "notification"
  private static let defaultTimeoutMs = 30_000
  private static let responseTimeoutMs = 10_000
  private static let ledger = WakeLockLedger(
    begin: { name, expired in
      let task = UIApplication.shared.beginBackgroundTask(withName: name) { expired() }
      return task == .invalid ? nil : task.rawValue
    },
    end: { UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: $0)) },
    schedule: MainActorTimer.schedule)

  private let channel: Channel

  private init(channel: Channel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    for channel in Channel.allCases {
      registrar.addMethodCallDelegate(
        WakeLockPlugin(channel: channel),
        channel: FlutterMethodChannel(
          name: channel.rawValue, binaryMessenger: registrar.messenger()))
    }
  }

  static func holdForNotificationResponse() {
    ledger.holdResponse(timeoutMs: responseTimeoutMs)
  }

  static func releaseNotificationResponse() {
    ledger.release(WakeLockLedger.responseTag)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let tag = arguments?["tag"] as? String ?? Self.defaultTag
    switch (channel, call.method) {
    case (.wakeLock, "acquire"):
      let timeoutMs = (arguments?["timeoutMs"] as? NSNumber)?.intValue ?? Self.defaultTimeoutMs
      Self.ledger.acquire(tag, timeoutMs: timeoutMs)
      result(nil)
    case (.wakeLock, "release"):
      Self.ledger.release(tag)
      result(nil)
    case (.pushWakeLock, "release"):
      result(nil)
    case (.pushWakeLock, "appInFront"):
      result(UIApplication.shared.applicationState == .active)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

@MainActor
final class WakeLockLedger {
  typealias Begin =
    @MainActor (
      _ name: String, _ expired: @escaping @MainActor @Sendable () -> Void
    ) -> Int?
  typealias End = @MainActor (_ task: Int) -> Void
  typealias Schedule =
    @MainActor (
      _ milliseconds: Int, _ fire: @escaping @MainActor @Sendable () -> Void
    ) -> @MainActor () -> Void

  static let responseTag = "notification_response"

  private struct Held {
    let task: Int
    let generation: Int
    let cancelTimeout: @MainActor () -> Void
  }

  private let begin: Begin
  private let end: End
  private let schedule: Schedule
  private var held: [String: Held] = [:]
  private var generation = 0

  init(begin: @escaping Begin, end: @escaping End, schedule: @escaping Schedule) {
    self.begin = begin
    self.end = end
    self.schedule = schedule
  }

  var heldTags: Set<String> { Set(held.keys) }

  func acquire(_ tag: String, timeoutMs: Int) {
    hold(tag, timeoutMs: timeoutMs)
    if tag != Self.responseTag {
      release(Self.responseTag)
    }
  }

  func holdResponse(timeoutMs: Int) {
    hold(Self.responseTag, timeoutMs: timeoutMs)
  }

  func release(_ tag: String) {
    guard let lock = held.removeValue(forKey: tag) else { return }
    lock.cancelTimeout()
    end(lock.task)
  }

  private func hold(_ tag: String, timeoutMs: Int) {
    release(tag)
    generation += 1
    let current = generation
    guard
      let task = begin("zuno:\(tag)", { [weak self] in self?.expire(tag, generation: current) })
    else { return }
    let cancelTimeout = schedule(max(timeoutMs, 0)) { [weak self] in
      self?.expire(tag, generation: current)
    }
    held[tag] = Held(task: task, generation: current, cancelTimeout: cancelTimeout)
  }

  private func expire(_ tag: String, generation: Int) {
    guard held[tag]?.generation == generation else { return }
    release(tag)
  }
}

@MainActor
final class ClientLeasePlugin: NSObject, @preconcurrency FlutterPlugin {
  private static let log = Logger(subsystem: "im.zuno.chat", category: "client-lease")
  private static var engines = 0
  private static var channels: [Int: FlutterMethodChannel] = [:]
  private static let ledger = ClientLeaseLedger(
    makeToken: { UUID().uuidString },
    schedule: MainActorTimer.schedule,
    sendYield: { channels[$0]?.invokeMethod("yield", arguments: nil) },
    log: { log.notice("\($0, privacy: .public)") })

  private let engine: Int

  private init(engine: Int) {
    self.engine = engine
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    engines += 1
    let plugin = ClientLeasePlugin(engine: engines)
    let channel = FlutterMethodChannel(
      name: "zuno/client_lease", binaryMessenger: registrar.messenger())
    channels[plugin.engine] = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    Self.channels[engine] = nil
    Self.ledger.detach(engine: engine)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "acquire":
      guard let kind = (arguments?["kind"] as? String).flatMap(ClientLeaseKind.init(rawValue:))
      else {
        result(
          FlutterError(code: "bad_args", message: "kind must be app or background", details: nil))
        return
      }
      let waitMs = (arguments?["waitMs"] as? NSNumber)?.intValue ?? 0
      Self.ledger.acquire(engine: engine, kind: kind, waitMs: waitMs) { result($0) }
    case "release":
      if let token = arguments?["token"] as? String {
        Self.ledger.release(token: token)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

enum ClientLeaseKind: String, Sendable {
  case app
  case background
}

@MainActor
final class ClientLeaseLedger {
  typealias Reply = @MainActor (_ token: String?) -> Void
  typealias Schedule =
    @MainActor (
      _ milliseconds: Int, _ fire: @escaping @MainActor @Sendable () -> Void
    ) -> @MainActor () -> Void

  private enum Decision {
    case grant
    case deny
    case wait
  }

  private struct Grant {
    let engine: Int
    let kind: ClientLeaseKind
  }

  private struct Waiter {
    let id: Int
    let engine: Int
    let kind: ClientLeaseKind
    let reply: Reply
    let cancelTimer: @MainActor () -> Void
  }

  private let makeToken: @MainActor () -> String
  private let schedule: Schedule
  private let sendYield: @MainActor (_ engine: Int) -> Void
  private let log: @MainActor (_ message: String) -> Void
  private var grants: [String: Grant] = [:]
  private var waiters: [Waiter] = []
  private var lastWaiterId = 0
  private var askedToYield: Set<Int> = []

  init(
    makeToken: @escaping @MainActor () -> String, schedule: @escaping Schedule,
    sendYield: @escaping @MainActor (_ engine: Int) -> Void,
    log: @escaping @MainActor (_ message: String) -> Void
  ) {
    self.makeToken = makeToken
    self.schedule = schedule
    self.sendYield = sendYield
    self.log = log
  }

  var holders: [Int: ClientLeaseKind] {
    var holders: [Int: ClientLeaseKind] = [:]
    for grant in grants.values where holders[grant.engine] != .app {
      holders[grant.engine] = grant.kind
    }
    return holders
  }

  var waitingEngines: [Int] { waiters.map(\.engine) }

  func acquire(engine: Int, kind: ClientLeaseKind, waitMs: Int, reply: @escaping Reply) {
    switch decide(engine: engine, kind: kind) {
    case .grant:
      reply(grant(engine: engine, kind: kind))
    case .deny:
      reply(nil)
    case .wait:
      lastWaiterId += 1
      let id = lastWaiterId
      let cancelTimer = schedule(max(waitMs, 0)) { [weak self] in self?.timeOut(id) }
      let waiter = Waiter(
        id: id, engine: engine, kind: kind, reply: reply, cancelTimer: cancelTimer)
      if kind == .app, let firstBackground = waiters.firstIndex(where: { $0.kind == .background }) {
        waiters.insert(waiter, at: firstBackground)
      } else {
        waiters.append(waiter)
      }
      askHoldersToYield()
    }
  }

  func release(token: String) {
    guard grants.removeValue(forKey: token) != nil else { return }
    settle()
  }

  func detach(engine: Int) {
    grants = grants.filter { $0.value.engine != engine }
    let leaving = waiters.filter { $0.engine == engine }
    waiters.removeAll { $0.engine == engine }
    for waiter in leaving {
      waiter.cancelTimer()
      waiter.reply(nil)
    }
    settle()
  }

  private func decide(engine: Int, kind: ClientLeaseKind) -> Decision {
    let holders = holders
    if holders[engine] != nil || holders.isEmpty { return .grant }
    if holders.values.contains(.app) { return kind == .app ? .wait : .deny }
    return .wait
  }

  private func grant(engine: Int, kind: ClientLeaseKind) -> String {
    let token = makeToken()
    grants[token] = Grant(engine: engine, kind: kind)
    return token
  }

  private func settle() {
    while let next = nextSettled() {
      let waiter = waiters.remove(at: next.index)
      waiter.cancelTimer()
      waiter.reply(next.granted ? grant(engine: waiter.engine, kind: waiter.kind) : nil)
    }
    askHoldersToYield()
  }

  private func nextSettled() -> (index: Int, granted: Bool)? {
    for (index, waiter) in waiters.enumerated() {
      switch decide(engine: waiter.engine, kind: waiter.kind) {
      case .grant: return (index, true)
      case .deny: return (index, false)
      case .wait: continue
      }
    }
    return nil
  }

  private func askHoldersToYield() {
    let holders = holders
    askedToYield.formIntersection(holders.keys)
    guard !waiters.isEmpty else { return }
    for (engine, kind) in holders.sorted(by: { $0.key < $1.key })
    where kind == .background && !askedToYield.contains(engine) {
      askedToYield.insert(engine)
      sendYield(engine)
    }
  }

  private func timeOut(_ id: Int) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    let waiter = waiters.remove(at: index)
    switch waiter.kind {
    case .app:
      let others = holders.keys.sorted()
      let token = grant(engine: waiter.engine, kind: .app)
      log("force-granted an app lease to engine \(waiter.engine) while engines \(others) held it")
      waiter.reply(token)
    case .background:
      waiter.reply(nil)
    }
    settle()
  }
}
