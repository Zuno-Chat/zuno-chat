import Foundation

struct DeliveredNote: Equatable, Sendable {
  let identifier: String
  let thread: String
  let roomToken: String?
  let seconds: Int?
  var appPosted = false
}

extension DeliveredNote {
  init(identifier: String, thread: String, userInfo: [AnyHashable: Any], pushed: Bool = true) {
    self.init(
      identifier: identifier, thread: thread, roomToken: userInfo["t"] as? String,
      seconds: Self.seconds(userInfo["o"]),
      appPosted: !pushed && !CatchUpComposer.isCatchUp(identifier))
  }

  private static func seconds(_ value: Any?) -> Int? {
    if let text = value as? String { return Int(text) }
    return (value as? NSNumber)?.intValue
  }
}

struct ThreadRead: Equatable, Sendable {
  let token: String
  let upToMs: Int64?
}

enum DeliveredSweep {
  static func identifiersToRemove(_ delivered: [DeliveredNote], reads: [ThreadRead]) -> [String] {
    let reads = reads.filter { !$0.token.isEmpty }
    guard !reads.isEmpty else { return [] }
    return delivered.filter { note in reads.contains { covers($0, note) } }.map(\.identifier)
  }

  private static func covers(_ read: ThreadRead, _ note: DeliveredNote) -> Bool {
    guard !note.appPosted else { return false }
    guard note.roomToken == read.token || note.thread == read.token else { return false }
    guard let upTo = read.upToMs else { return true }
    guard let seconds = note.seconds else { return false }
    return Int64(seconds) <= upTo / 1000
  }
}
