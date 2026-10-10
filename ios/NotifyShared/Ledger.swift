import Foundation

struct Ledger: Codable, Equatable, Sendable {
  enum State: String, Codable, Sendable {
    case ringing
    case answered
    case ended
    case declined
    case missed
  }

  enum Source: String, Codable, Sendable {
    case push
    case sync
  }

  struct Entry: Codable, Equatable, Sendable {
    var uuid: String
    var t: String
    var state: State
    var source: Source
    var ts: Int64
  }

  static let fileName = "ledger"
  static let limit = 64

  var v: Int
  var calls: [Entry]

  init(calls: [Entry] = []) {
    v = 1
    self.calls = calls
  }

  mutating func record(
    uuid: UUID, roomToken: String, state: State, source: Source, at ts: Int64
  ) {
    let id = uuid.uuidString
    let previous = calls.first { $0.uuid == id }
    calls.removeAll { $0.uuid == id }
    calls.append(
      Entry(
        uuid: id, t: roomToken.isEmpty ? previous?.t ?? "" : roomToken, state: state,
        source: previous?.source ?? source, ts: ts))
    if calls.count > Self.limit {
      calls.removeFirst(calls.count - Self.limit)
    }
  }

  func entry(for uuid: UUID) -> Entry? {
    calls.last { $0.uuid == uuid.uuidString }
  }

  func isResolved(_ uuid: UUID) -> Bool {
    guard let entry = entry(for: uuid) else { return false }
    return entry.state != .ringing
  }

  var resolved: Set<UUID> {
    Set(calls.filter { $0.state != .ringing }.compactMap { UUID(uuidString: $0.uuid) })
  }

  func encoded() -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return CaughtErrors.attempt("ledger encode") { try encoder.encode(self) }
      ?? Data(#"{"calls":[],"v":1}"#.utf8)
  }

  static func decoded(_ data: Data) -> Ledger? {
    let ledger = CaughtErrors.attempt("ledger decode") {
      try JSONDecoder().decode(Ledger.self, from: data)
    }
    return ledger?.v == 1 ? ledger : nil
  }
}
