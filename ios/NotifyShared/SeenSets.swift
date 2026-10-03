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

struct NseUtd: Equatable, Sendable {
  let room: String
  let event: String
  let ts: Int64
}

struct NseStateFile: Equatable, Sendable {
  var replay: [String] = []
  var utd: [NseUtd] = []
  var missed: [String] = []
  var version: String?

  static func decode(_ data: Data?) -> NseStateFile {
    guard let data, let json = NseJson.parse(data) else { return NseStateFile() }
    let utd = (json["utd"]?.array ?? []).compactMap { item -> NseUtd? in
      guard let room = item["room"]?.string, let event = item["event"]?.string,
        let ts = item["ts"]?.int64
      else { return nil }
      return NseUtd(room: room, event: event, ts: ts)
    }
    return NseStateFile(
      replay: json["replay"]?.array?.compactMap(\.string) ?? [], utd: utd,
      missed: json["missed"]?.array?.compactMap(\.string) ?? [],
      version: json["version"]?.string)
  }

  func encoded() -> Data {
    var object: [String: Any] = [
      "v": 1, "replay": replay, "missed": missed,
      "utd": utd.map { ["room": $0.room, "event": $0.event, "ts": $0.ts] },
    ]
    if let version { object["version"] = version }
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }
}

enum SeenSets {
  static let shownLimit = 256
  static let replayLimit = 512
  static let utdLimit = 200
  static let missedLimit = 64
  static let marksLimit = 64

  static func appending(_ value: String, to list: [String], limit: Int) -> [String] {
    var updated = list.filter { $0 != value }
    updated.append(value)
    return updated.count > limit ? Array(updated.suffix(limit)) : updated
  }

  static func tokens(_ data: Data?) -> [String] {
    guard let data, let json = NseJson.parse(data) else { return [] }
    return json["e"]?.array?.compactMap(\.string) ?? []
  }

  static func encodeTokens(_ tokens: [String]) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["v": 1, "e": tokens], options: [.sortedKeys]))
      ?? Data()
  }

  static func marks(_ data: Data?) -> [NseMark] {
    guard let data, let json = NseJson.parse(data) else { return [] }
    return (json["marks"]?.array ?? []).compactMap(NseMark.init)
  }

  static func encodeMarks(_ marks: [NseMark]) -> Data {
    let object: [String: Any] = ["v": 1, "marks": marks.map(\.json)]
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }
}

final class NseStateStore: Sendable {
  private static let lock = NSLock()
  let files: NseFiles

  init(files: NseFiles) {
    self.files = files
  }

  func meta() -> NseMeta? {
    files.read(NotifyFile.meta).flatMap(NseMeta.decode)
  }

  func room(token: String, roomId: String) -> NseRoomFile? {
    guard let room = files.read(NotifyFile.room(token)).flatMap(NseRoomFile.decode),
      room.room == roomId
    else { return nil }
    return room
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

  private func locked(_ body: () -> Void) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    body()
  }
}
