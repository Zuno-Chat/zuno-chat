import Foundation

enum NseOutcome: String, Sendable, CaseIterable {
  case shown
  case quiet
  case duplicate
  case hidden
  case read
  case gone
  case rateLimited = "rate_limited"
  case auth
  case route
  case net
  case utd
  case mismatch
  case bfu
  case noMeta = "no_meta"
  case test
  case nothing
  case fallbackRing = "fallback_ring"
  case callHandled = "call_handled"
  case safeMode = "safe_mode"
  case malformed
}

struct NseDelivery: Equatable, Sendable {
  enum Interruption: String, Equatable, Sendable {
    case active
    case passive
    case timeSensitive
  }

  enum Sound: String, Equatable, Sendable {
    case none
    case messageTone
    case ring
    case silentRing
    case original
  }

  var title: String
  var body: String
  var threadId: String
  var userInfo: [String: String]
  var interruption: Interruption
  var sound: Sound
  var badge: Int?
  var removals: [String]
  var usesOriginal: Bool
  var category: String? = nil

  static let passthrough = NseDelivery(
    title: "", body: "", threadId: NseComposer.fixedThread, userInfo: [:],
    interruption: .active, sound: .original, badge: nil, removals: [], usesOriginal: true)
}

struct NseResult: Equatable, Sendable {
  let delivery: NseDelivery
  let outcome: NseOutcome
}
