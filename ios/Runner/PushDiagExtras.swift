import Foundation

enum PushDiagExtras {
  enum SealedJSON {
    case found([String: Any])
    case missing
    case failed
  }

  static let logLines = 10
  static let ledgerLimit = 64
  static let logBytes = 64 * 1024

  static func collect(
    directory: URL?, readSealed: (String) -> SealedJSON, metrics: [[String: Any]] = []
  ) -> [String: Any] {
    var extras: [String: Any] = [:]
    if let ledger = ledger(readSealed("ledger")) { extras["ledger"] = ledger }
    if !metrics.isEmpty { extras["metrics"] = metrics }
    guard let directory else { return extras }
    let rooms = directory.appendingPathComponent("rooms", isDirectory: true)
    if let updated = newest([directory.appendingPathComponent("meta")] + children(of: rooms)) {
      extras["read_model"] = ["updated_ms": millis(updated)]
    }
    let log = directory.appendingPathComponent(NotifyFile.nseLog)
    var nse: [String: Any] = ["log": tail(of: log)]
    if let ran = modified(log) { nse["last_run_ms"] = millis(ran) }
    if case .found(let state) = readSealed("nse.state"), let version = state["version"] as? String {
      nse["version"] = version
    }
    extras["nse"] = nse
    extras["app"] = ["log": tail(of: directory.appendingPathComponent(NotifyFile.appLog))]
    return extras
  }

  static func ledger(_ read: SealedJSON) -> [[String: Any]]? {
    switch read {
    case .failed:
      return nil
    case .missing:
      return []
    case .found(let json):
      guard let calls = json["calls"] as? [Any] else { return nil }
      return calls.prefix(ledgerLimit).compactMap { raw -> [String: Any]? in
        guard let call = raw as? [String: Any], let state = call["state"] as? String,
          let source = call["source"] as? String, let ts = (call["ts"] as? NSNumber)?.int64Value
        else { return nil }
        return ["state": state, "source": source, "ts": ts]
      }
    }
  }

  static func tail(of url: URL) -> [String] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    let text = String(decoding: data.suffix(logBytes), as: UTF8.self)
    return text.split(whereSeparator: \.isNewline).suffix(logLines).map(String.init)
  }

  static func readSealed(_ name: String) -> SealedJSON {
    guard let store = NotifyStore.shared(), let secrets = NseLive.secrets() else { return .failed }
    switch store.read(name, key: secrets.readModelKey) {
    case .missing:
      return .missing
    case .unreadable, .corrupt:
      return .failed
    case .found(let data):
      guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return .failed
      }
      return .found(json)
    }
  }

  private static func children(of folder: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
  }

  private static func newest(_ urls: [URL]) -> Date? {
    urls.compactMap(modified).max()
  }

  private static func modified(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}
