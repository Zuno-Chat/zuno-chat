import Foundation

protocol NseFiles: Sendable {
  func read(_ name: String) -> Data?
  func write(_ name: String, _ data: Data) -> Bool
}

extension NotifyFile {
  static let shownApp = "shown.app"
  static let shownNse = "shown.nse"
  static let marks = "nse.marks"
  static let state = "nse.state"
}

struct NseMark: Equatable, Sendable {
  let kind: String
  let room: String?
  let call: String?
  let status: String?
  let ts: Int64

  var json: [String: Any] {
    var object: [String: Any] = ["kind": kind, "ts": ts]
    if let room { object["room"] = room }
    if let call { object["call"] = call }
    if let status { object["status"] = status }
    return object
  }

  init(kind: String, room: String? = nil, call: String? = nil, status: String? = nil, ts: Int64) {
    self.kind = kind
    self.room = room
    self.call = call
    self.status = status
    self.ts = ts
  }

  init?(_ json: NseJson) {
    guard let kind = json["kind"]?.string, let ts = json["ts"]?.int64 else { return nil }
    self.init(
      kind: kind, room: json["room"]?.string, call: json["call"]?.string,
      status: json["status"]?.string, ts: ts)
  }
}

struct NseStateFile: Equatable, Sendable {
  var replay: [String] = []
  var missed: [String] = []
  var pending: [String: Double] = [:]
  var version: String?

  static func decode(_ data: Data?) -> NseStateFile {
    guard let data, let json = NseJson.parse(data, "nse state parse") else {
      return NseStateFile()
    }
    return NseStateFile(
      replay: json["replay"]?.array?.compactMap(\.string) ?? [],
      missed: json["missed"]?.array?.compactMap(\.string) ?? [],
      pending: json["pending"]?.object?.compactMapValues(\.double) ?? [:],
      version: json["version"]?.string)
  }

  func encoded() -> Data {
    var object: [String: Any] = [
      "v": 1, "replay": replay, "missed": missed, "pending": pending,
    ]
    if let version { object["version"] = version }
    return NseJson.data(object, "nse state encode") ?? Data()
  }
}

enum SeenSets {
  static let shownLimit = 256
  static let replayLimit = 512
  static let missedLimit = 64
  static let marksLimit = 64

  static func appending(_ value: String, to list: [String], limit: Int) -> [String] {
    var updated = list.filter { $0 != value }
    updated.append(value)
    return updated.count > limit ? Array(updated.suffix(limit)) : updated
  }

  static func tokens(_ data: Data?) -> [String] {
    guard let data, let json = NseJson.parse(data, "nse tokens parse") else { return [] }
    return json["e"]?.array?.compactMap(\.string) ?? []
  }

  static func encodeTokens(_ tokens: [String]) -> Data {
    NseJson.data(["v": 1, "e": tokens], "nse tokens encode") ?? Data()
  }

  static func marks(_ data: Data?) -> [NseMark] {
    guard let data, let json = NseJson.parse(data, "nse marks parse") else { return [] }
    return (json["marks"]?.array ?? []).compactMap(NseMark.init)
  }

  static func encodeMarks(_ marks: [NseMark]) -> Data {
    let object: [String: Any] = ["v": 1, "marks": marks.map(\.json)]
    return NseJson.data(object, "nse marks encode") ?? Data()
  }
}

final class NseStateStore: Sendable {
  private static let lock = NSLock()
  let files: NseFiles

  init(files: NseFiles) {
    self.files = files
  }

  func meta() -> NotifyMeta? {
    files.read(NotifyFile.meta).flatMap(NotifyMeta.decoded)
  }

  func room(token: String, roomId: String) -> NotifyRoomFile? {
    files.read(NotifyFile.room(token)).flatMap { NotifyRoomFile.decoded($0, roomId: roomId) }
  }

  func ledger() -> Ledger {
    files.read(NotifyFile.ledger).flatMap(Ledger.decoded) ?? Ledger()
  }

  func shown(_ name: String) -> [String] {
    SeenSets.tokens(files.read(name))
  }

  func isShown(_ token: String) -> Bool {
    shown(NotifyFile.shownNse).contains(token) || shown(NotifyFile.shownApp).contains(token)
  }

  func recordShown(_ tokens: [String], in name: String) {
    locked {
      var list = shown(name)
      for token in tokens {
        list = SeenSets.appending(token, to: list, limit: SeenSets.shownLimit)
      }
      _ = files.write(name, SeenSets.encodeTokens(list))
    }
  }

  func claim(_ token: String) -> Bool {
    locked { take(token) }
  }

  func claimPending(_ token: String, process: Double) -> Bool {
    locked {
      guard take(token) else { return false }
      var state = self.state()
      state.pending[token] = process
      _ = files.write(NotifyFile.state, state.encoded())
      return true
    }
  }

  func settle(_ token: String) {
    locked {
      var state = self.state()
      guard state.pending.removeValue(forKey: token) != nil else { return }
      _ = files.write(NotifyFile.state, state.encoded())
    }
  }

  func release(_ token: String) {
    locked { give(back: [token]) }
  }

  func releaseAbandoned(process: Double) {
    locked {
      let abandoned = state().pending.filter { $0.value != process }.keys
      if !abandoned.isEmpty { give(back: Set(abandoned)) }
    }
  }

  private func take(_ token: String) -> Bool {
    guard !isShown(token) else { return false }
    let list = SeenSets.appending(
      token, to: shown(NotifyFile.shownNse), limit: SeenSets.shownLimit)
    _ = files.write(NotifyFile.shownNse, SeenSets.encodeTokens(list))
    return true
  }

  private func give(back tokens: Set<String>) {
    let list = shown(NotifyFile.shownNse).filter { !tokens.contains($0) }
    _ = files.write(NotifyFile.shownNse, SeenSets.encodeTokens(list))
    var state = self.state()
    let before = state.pending.count
    state.pending = state.pending.filter { !tokens.contains($0.key) }
    if state.pending.count != before { _ = files.write(NotifyFile.state, state.encoded()) }
  }

  func state() -> NseStateFile {
    NseStateFile.decode(files.read(NotifyFile.state))
  }

  func updateState(_ change: (inout NseStateFile) -> Void) {
    locked {
      var state = self.state()
      change(&state)
      _ = files.write(NotifyFile.state, state.encoded())
    }
  }

  func marks() -> [NseMark] {
    SeenSets.marks(files.read(NotifyFile.marks))
  }

  func appendMark(_ mark: NseMark) {
    locked {
      var marks = self.marks()
      marks.append(mark)
      if marks.count > SeenSets.marksLimit { marks = Array(marks.suffix(SeenSets.marksLimit)) }
      _ = files.write(NotifyFile.marks, SeenSets.encodeMarks(marks))
    }
  }

  private func locked<Result>(_ body: () -> Result) -> Result {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return body()
  }
}
