import Foundation

struct ServerClock: Equatable, Sendable {
  static let deviceTolerance: Int64 = 60_000

  var offsetMs: Int64?

  func now(deviceMs: Int64, atLeast floor: Int64 = .min) -> Int64 {
    max(deviceMs + (offsetMs ?? 0), floor)
  }

  func isStale(expirySeconds: UInt32, deviceMs: Int64, atLeast floor: Int64 = .min) -> Bool {
    let expiryMs = Int64(expirySeconds) * 1000
    guard offsetMs != nil else {
      return max(deviceMs, floor) > expiryMs + Self.deviceTolerance
    }
    return now(deviceMs: deviceMs, atLeast: floor) > expiryMs
  }

  func ringSeconds(
    expirySeconds: UInt32, deviceMs: Int64, atLeast floor: Int64 = .min, cap: Int
  ) -> Int {
    let remaining = Int64(expirySeconds) * 1000 - now(deviceMs: deviceMs, atLeast: floor) + 5000
    return Int(min(Int64(cap), max(5, remaining / 1000)))
  }

  mutating func observe(serverMs: Int64, deviceMs: Int64) {
    offsetMs = serverMs - deviceMs
  }
}
