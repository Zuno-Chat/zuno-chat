import CryptoKit
import Foundation
import UserNotifications
import os

struct LiveNseFiles: NseFiles {
  let store: NotifyStore
  let key: SymmetricKey

  func read(_ name: String) -> Data? {
    guard case .found(let data) = store.read(name, key: key) else { return nil }
    return data
  }

  func write(_ name: String, _ data: Data) -> Bool {
    do {
      try store.write(name, plaintext: data, key: key)
      return true
    } catch {
      CaughtErrors.record("nse file write", error)
      return false
    }
  }
}

struct LiveNseHashing: NseHashing {
  let key: SymmetricKey

  func t(_ roomId: String) -> String { OpaqueIds.roomToken(roomId, installKey: key) }
  func e(_ value: String) -> String { OpaqueIds.eventToken(value, installKey: key) }
  func rg(_ callUuid: UUID) -> String { OpaqueIds.ringToken(callUuid, installKey: key) }
}

final class LiveNseTransport: NseTransport, @unchecked Sendable {
  static let shared = LiveNseTransport()
  static let maxBodyBytes = 256 * 1024

  private let session: URLSession

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  func post(_ url: URL, authorization: String, body: Data, timeoutMs: Int) async
    -> NseHttpResult
  {
    let request = Self.request(url, authorization: authorization, body: body, timeoutMs: timeoutMs)
    return await withTaskGroup(of: NseHttpResult.self) { group in
      group.addTask { await self.send(request) }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
        return .timeout
      }
      let first = await group.next() ?? .timeout
      group.cancelAll()
      return first
    }
  }

  static func request(_ url: URL, authorization: String, body: Data, timeoutMs: Int) -> URLRequest {
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: Double(max(1, timeoutMs)) / 1000)
    request.httpMethod = "POST"
    request.setValue(authorization, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return request
  }

  private func send(_ request: URLRequest) async -> NseHttpResult {
    do {
      let (bytes, response) = try await session.bytes(for: request)
      guard let http = response as? HTTPURLResponse else { return .failure }
      var data = Data()
      for try await byte in bytes {
        data.append(byte)
        if data.count > Self.maxBodyBytes { return .failure }
      }
      var headers: [String: String] = [:]
      for (key, value) in http.allHeaderFields {
        if let name = key as? String { headers[name.lowercased()] = "\(value)" }
      }
      return .response(status: http.statusCode, headers: headers, body: data)
    } catch let error as URLError {
      switch error.code {
      case .timedOut: return .timeout
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
        return .offline
      case .cancelled: return .failure
      default:
        CaughtErrors.record("nse fetch", error)
        return .failure
      }
    } catch is CancellationError {
      return .failure
    } catch {
      CaughtErrors.record("nse fetch", error)
      return .failure
    }
  }
}

struct LiveNseCenter: NseDeliveredCenter {
  func delivered() async -> [NseDelivered] {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        continuation.resume(returning: notifications.map(NseContentFactory.delivered))
      }
    }
  }
}

final class LiveNseDefaults: NseDefaults, @unchecked Sendable {
  private let defaults: UserDefaults

  init(_ defaults: UserDefaults) {
    self.defaults = defaults
  }

  func double(_ key: String) -> Double { defaults.double(forKey: key) }
  func integer(_ key: String) -> Int { defaults.integer(forKey: key) }

  func crumbs(_ key: String) -> [String: Double] {
    defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
  }

  func set(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
  func set(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
  func setCrumbs(_ value: [String: Double], forKey key: String) { defaults.set(value, forKey: key) }
  func remove(_ key: String) { defaults.removeObject(forKey: key) }

  func keys(withPrefix prefix: String) -> [String] {
    defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }.sorted()
  }
}

struct LiveNseSignals: NseSignals {
  static let logger = Logger(subsystem: "im.zuno.chat", category: "nse")

  let deliveryLog: DeliveryLog

  func post(_ hint: DarwinHint) { hint.post() }

  func log(_ event: String, _ fields: [(String, String)]) {
    deliveryLog.append(event, fields)
    let line = ([event] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    Self.logger.notice("\(line, privacy: .public)")
  }
}

struct LiveNseClock: NseClock {
  func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  func wait(ms: Int, wakeOn hints: [DarwinHint]) async {
    let semaphore = DispatchSemaphore(value: 0)
    let tokens = hints.map { DarwinHintCenter.shared.observe($0) { semaphore.signal() } }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        _ = semaphore.wait(timeout: .now() + .milliseconds(max(0, ms)))
        continuation.resume()
      }
    }
    for token in tokens { DarwinHintCenter.shared.remove(token) }
  }
}

enum NseMemory {
  static func footprint() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
  }
}

enum NseLive {
  static let processStart = Date().timeIntervalSince1970

  static func environment(bundle: Bundle = .main) -> NseEnvironment? {
    guard let group = NotifyStore.groupIdentifier(bundle: bundle),
      let store = NotifyStore.shared(bundle: bundle),
      let suite = UserDefaults(suiteName: group)
    else { return nil }
    return NseEnvironment(
      keychain: NotifyKeychain(accessGroup: group),
      files: { LiveNseFiles(store: store, key: $0.readModelKey) },
      hashing: { LiveNseHashing(key: $0.tokenKey) }, transport: LiveNseTransport.shared,
      decryptor: VodozemacMegolm.shared, center: LiveNseCenter(), clock: LiveNseClock(),
      defaults: LiveNseDefaults(suite),
      signals: LiveNseSignals(deliveryLog: DeliveryLog(url: store.url(NotifyFile.nseLog))),
      processStart: processStart, footprint: { NseMemory.footprint() },
      version: version(bundle))
  }

  static func version(_ bundle: Bundle) -> String {
    let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return "\(short ?? "?") (\(build ?? "?"))"
  }

  static func secrets(bundle: Bundle = .main) -> NotifySecrets? {
    NsePipeline.ready(
      NotifyKeychain(accessGroup: NotifyStore.groupIdentifier(bundle: bundle)).secrets())
  }
}
