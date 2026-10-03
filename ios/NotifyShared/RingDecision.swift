import Foundation

enum RingSession: Equatable, Sendable {
  case signedIn(userId: String)
  case signedOut
  case noSession
}

enum RingEndReason: String, Equatable, Sendable {
  case failed
  case unanswered
  case remoteEnded
}

struct CallsSnapshot: Equatable, Sendable {
  var ringing: UUID?
  var active: UUID?
  var identities: [UUID: UUID]
  var resolved: Set<UUID>

  init(
    ringing: UUID? = nil, active: UUID? = nil, identities: [UUID: UUID] = [:],
    resolved: Set<UUID> = []
  ) {
    self.ringing = ringing
    self.active = active
    self.identities = identities
    self.resolved = resolved
  }

  var busy: UUID? { ringing ?? active }
}

struct RingCall: Equatable, Sendable {
  let uuid: UUID
  let roomId: String
  let callId: String
  let callerId: String
  let name: String
  let video: Bool
  let ringSeconds: Int
}

struct GenericRing: Equatable, Sendable {
  let uuid: UUID
  let ringSeconds: Int
  let beforeFirstUnlock: Bool
}

enum RingAction: Equatable, Sendable {
  case ring(RingCall)
  case generic(GenericRing)
  case update(uuid: UUID, name: String, video: Bool, reportAgain: Bool)
  case duplicate(UUID)
  case reportThenEnd(uuid: UUID, reason: RingEndReason)
  case complete
}

struct RingOutcome: Equatable, Sendable {
  var action: RingAction
  var log: String
  var disablePushTypes = false
  var reregister = false
  var prewarm = false
}

struct RingInput: Sendable {
  var blob: VoipBlobOpen
  var mustReport: Bool?
  var beforeFirstUnlock: Bool
  var session: RingSession
  var nowMs: Int64
  var clock: ServerClock
  var calls: CallsSnapshot
  var unknownKidRecent: Int
  var level: PreviewLevel
  var placeholder: UUID
  var room: @Sendable (String) -> RoomTitleFile?
}

enum RingDecision {
  static let ringCap = 55
  static let genericRingCap = 45
  static let unknownKidAllowance = 2

  static func decide(_ input: RingInput) -> RingOutcome {
    if input.beforeFirstUnlock {
      return beforeFirstUnlock(input)
    }
    switch input.session {
    case .signedOut:
      return end(input, log: "signed_out", reason: .remoteEnded, disablePushTypes: true)
    case .noSession:
      return end(input, log: "no_session", reason: .remoteEnded, disablePushTypes: true)
    case .signedIn(let userId):
      switch input.blob {
      case .forged:
        return end(input, log: "forged", reason: .failed)
      case .unknownVersion:
        return generic(input, expiry: nil, log: "version_unknown")
      case .unknownKid(let header):
        return generic(input, expiry: header.expiry, log: "kid_unknown")
      case .opened(let header, let ring):
        return opened(input, header: header, ring: ring, userId: userId)
      }
    }
  }

  private static func opened(
    _ input: RingInput, header: VoipBlobHeader, ring: VoipRing, userId: String
  ) -> RingOutcome {
    let skip = input.mustReport == false
    if ring.kind == .canary {
      return end(input, log: "canary", reason: .remoteEnded)
    }
    if ring.caller == userId {
      return end(input, log: "own_call", reason: .remoteEnded)
    }
    let identity = CallIdentity.uuid(roomId: ring.room, callId: ring.call)
    let name = CallerName.display(level: input.level, room: input.room(ring.room), ring: ring)
    if let tracked = input.calls.identities[identity] {
      return RingOutcome(
        action: .update(uuid: tracked, name: name, video: ring.kind == .video, reportAgain: !skip),
        log: "duplicate", prewarm: true)
    }
    if input.clock.isStale(expirySeconds: header.expiry, deviceMs: input.nowMs, atLeast: ring.ts) {
      return end(input, log: "stale", reason: .unanswered)
    }
    if input.calls.resolved.contains(identity) {
      return end(input, log: "resolved", reason: .unanswered)
    }
    if let ringing = input.calls.ringing {
      return RingOutcome(action: skip ? .complete : .duplicate(ringing), log: "busy_ringing")
    }
    if let active = input.calls.active {
      return RingOutcome(action: skip ? .complete : .duplicate(active), log: "busy_active")
    }
    let seconds = input.clock.ringSeconds(
      expirySeconds: header.expiry, deviceMs: input.nowMs, atLeast: ring.ts, cap: ringCap)
    return RingOutcome(
      action: .ring(
        RingCall(
          uuid: identity, roomId: ring.room, callId: ring.call, callerId: ring.caller,
          name: name, video: ring.kind == .video, ringSeconds: seconds)),
      log: "ring", prewarm: true)
  }

  private static func generic(_ input: RingInput, expiry: UInt32?, log: String) -> RingOutcome {
    if let expiry, input.clock.isStale(expirySeconds: expiry, deviceMs: input.nowMs) {
      return end(input, log: "stale", reason: .unanswered)
    }
    if input.unknownKidRecent >= unknownKidAllowance {
      var outcome = end(input, log: "\(log)_limit", reason: .failed)
      outcome.reregister = true
      return outcome
    }
    if let busy = input.calls.busy {
      return RingOutcome(
        action: input.mustReport == false ? .complete : .duplicate(busy), log: "\(log)_busy",
        reregister: true)
    }
    let seconds =
      expiry.map {
        input.clock.ringSeconds(expirySeconds: $0, deviceMs: input.nowMs, cap: genericRingCap)
      } ?? genericRingCap
    return RingOutcome(
      action: .generic(
        GenericRing(uuid: input.placeholder, ringSeconds: seconds, beforeFirstUnlock: false)),
      log: log, reregister: true, prewarm: true)
  }

  private static func beforeFirstUnlock(_ input: RingInput) -> RingOutcome {
    let expiry: UInt32?
    switch input.blob {
    case .unknownKid(let header):
      expiry = header.expiry
    case .unknownVersion:
      expiry = nil
    case .opened, .forged:
      return end(input, log: "bfu_unreadable", reason: .failed)
    }
    if let expiry,
      ServerClock(offsetMs: nil).isStale(expirySeconds: expiry, deviceMs: input.nowMs)
    {
      return end(input, log: "bfu_stale", reason: .unanswered)
    }
    if input.mustReport == false {
      return RingOutcome(action: .complete, log: "bfu_skipped")
    }
    if let busy = input.calls.busy {
      return RingOutcome(action: .duplicate(busy), log: "bfu_busy")
    }
    return RingOutcome(
      action: .generic(
        GenericRing(
          uuid: input.placeholder, ringSeconds: genericRingCap, beforeFirstUnlock: true)),
      log: "bfu_ring")
  }

  private static func end(
    _ input: RingInput, log: String, reason: RingEndReason, disablePushTypes: Bool = false
  ) -> RingOutcome {
    let action: RingAction
    if input.mustReport == false {
      action = .complete
    } else if let busy = input.calls.busy {
      action = .duplicate(busy)
    } else {
      action = .reportThenEnd(uuid: input.placeholder, reason: reason)
    }
    return RingOutcome(action: action, log: log, disablePushTypes: disablePushTypes)
  }
}

enum CallerName {
  static let generic = "Zuno call"
  static let byteLimit = 64

  static func display(level: PreviewLevel, room: RoomTitleFile?, ring: VoipRing) -> String {
    guard level != .none else { return generic }
    if let room, room.room == ring.room,
      let chosen = named(room.dm && !room.partner.isEmpty ? room.partner : room.title)
    {
      return chosen
    }
    return named(ring.rname.isEmpty ? ring.cname : ring.rname) ?? generic
  }

  static func shown(_ name: String, level: PreviewLevel) -> String {
    guard level != .none else { return generic }
    return named(name) ?? generic
  }

  static func sanitize(_ text: String) -> String {
    var kept = String.UnicodeScalarView()
    var bytes = 0
    for scalar in text.unicodeScalars where !isStripped(scalar) {
      let size = utf8Length(scalar.value)
      guard bytes + size <= byteLimit else { break }
      bytes += size
      kept.append(scalar)
    }
    return String(kept)
  }

  private static func named(_ text: String) -> String? {
    let clean = sanitize(text)
    return clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clean
  }

  static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0000...0x001F, 0x007F...0x009F, 0x061C, 0x200E, 0x200F, 0x202A...0x202E,
      0x2066...0x2069:
      return true
    default:
      return false
    }
  }

  private static func utf8Length(_ value: UInt32) -> Int {
    switch value {
    case 0..<0x80: return 1
    case 0x80..<0x800: return 2
    case 0x800..<0x10000: return 3
    default: return 4
    }
  }
}
