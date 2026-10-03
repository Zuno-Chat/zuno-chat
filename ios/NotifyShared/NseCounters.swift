import Foundation

final class NseCounters: Sendable {
  static let prefix = "nse.c."
  private static let lock = NSLock()

  private let defaults: NseDefaults

  init(defaults: NseDefaults) {
    self.defaults = defaults
  }

  func record(
    _ outcome: NseOutcome, nowMs: Int64, durationMs: Int64, footprintBytes: UInt64?,
    readModelAgeMs: Int64?
  ) {
    let day = "\(Self.prefix)\(Self.day(nowMs))"
    var keys = ["\(day).o.\(outcome.rawValue)", "\(day).d.\(Self.durationBucket(durationMs))"]
    if let footprintBytes { keys.append("\(day).m.\(Self.footprintBucket(footprintBytes))") }
    if let readModelAgeMs { keys.append("\(day).a.\(Self.ageBucket(readModelAgeMs))") }
    Self.lock.lock()
    defer { Self.lock.unlock() }
    for key in keys { defaults.set(defaults.integer(key) + 1, forKey: key) }
  }

  static func day(_ ms: Int64) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let parts = calendar.dateComponents(
      [.year, .month, .day], from: Date(timeIntervalSince1970: Double(ms) / 1000))
    return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func durationBucket(_ ms: Int64) -> String {
    switch ms {
    case ..<1000: return "lt1s"
    case ..<3000: return "lt3s"
    case ..<8000: return "lt8s"
    case ..<25000: return "lt25s"
    default: return "ge25s"
    }
  }

  static func footprintBucket(_ bytes: UInt64) -> String {
    switch bytes / 1_048_576 {
    case ..<6: return "lt6mb"
    case ..<12: return "lt12mb"
    case ..<20: return "lt20mb"
    default: return "ge20mb"
    }
  }

  static func ageBucket(_ ms: Int64) -> String {
    switch ms {
    case ..<300_000: return "lt5m"
    case ..<3_600_000: return "lt1h"
    case ..<28_800_000: return "lt8h"
    case ..<86_400_000: return "lt24h"
    case ..<604_800_000: return "lt7d"
    default: return "ge7d"
    }
  }
}
