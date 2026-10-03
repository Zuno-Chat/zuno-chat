import Foundation
import PushKit
import UIKit

struct RingReported: Equatable, Sendable {
  let uuid: UUID
  let roomId: String?
}

@MainActor
final class PushRingHandler: NSObject {
  static let shared = PushRingHandler(
    calls: .shared, cache: .shared, keys: VoipKeyStore(),
    prewarm: { EngineHost.shared.startForRing() })

  static let tokenDefaultsKey = "zuno.voip.token"
  static let unknownKidWindow: TimeInterval = 600

  var onReported: @MainActor (RingReported) -> Void = { _ in }

  private let calls: CallKitCenter
  private let cache: ReadModelCache
  private let keys: VoipKeyStore
  private let prewarm: @MainActor () -> Void
  private let now: @MainActor () -> Date
  private let makeUUID: @MainActor () -> UUID
  private let defaults: UserDefaults
  private var registry: PKPushRegistry?
  private var unknownKid: [Date] = []
  private var keptBlobs: [UUID: Data] = [:]
  private var pendingEvents: [String] = []

  init(
    calls: CallKitCenter, cache: ReadModelCache, keys: VoipKeyStore,
    prewarm: @escaping @MainActor () -> Void,
    now: @escaping @MainActor () -> Date = { Date() },
    makeUUID: @escaping @MainActor () -> UUID = { UUID() },
    defaults: UserDefaults = .standard
  ) {
    self.calls = calls
    self.cache = cache
    self.keys = keys
    self.prewarm = prewarm
    self.now = now
    self.makeUUID = makeUUID
    self.defaults = defaults
  }

  func start() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = desiredPushTypes()
    self.registry = registry
    NotificationCenter.default.addObserver(
      self, selector: #selector(protectedDataBecameAvailable),
      name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
  }

  func desiredPushTypes() -> Set<PKPushType> {
    calls.isAvailable && cache.signedOut() != .present ? [.voIP] : []
  }

  var token: Data? {
    registry?.pushToken(for: .voIP)
  }

  func takeEvents() -> [String] {
    defer { pendingEvents.removeAll() }
    return pendingEvents
  }

  func setSignedIn(_ signedIn: Bool) {
    cache.setSignedOut(!signedIn)
    if !signedIn {
      keys.delete()
      calls.endAll(reason: .remoteEnded)
    }
    registry?.desiredPushTypes = desiredPushTypes()
  }

  func tokenUpdated(_ token: Data) {
    guard defaults.data(forKey: Self.tokenDefaultsKey) != token else { return }
    defaults.set(token, forKey: Self.tokenDefaultsKey)
    queue("token")
  }

  func tokenInvalidated() {
    defaults.removeObject(forKey: Self.tokenDefaultsKey)
    queue("invalidated")
  }

  func handle(
    payload: [AnyHashable: Any], mustReport: Bool?, completion: @escaping @Sendable () -> Void
  ) {
    let received = now()
    let nowMs = Int64(received.timeIntervalSince1970 * 1000)
    let blob = VoipBlob.data(from: payload)
    let keyRead = keys.load()
    let locked = keyRead == .locked
    let opened = VoipBlob.open(payload: payload) { kid in
      guard case .ready(let keys) = keyRead else { return nil }
      return keys.key(for: kid, nowMs: nowMs)
    }
    let meta = locked ? nil : cache.meta()
    var snapshot = calls.snapshot()
    var roomFile: RoomTitleFile?
    if !locked {
      snapshot.resolved.formUnion(cache.ledger().resolved)
      if case .opened(_, let ring) = opened {
        roomFile = cache.room(ring.room)
      }
    }
    unknownKid.removeAll { received.timeIntervalSince($0) > Self.unknownKidWindow }
    let input = RingInput(
      blob: opened, mustReport: mustReport, beforeFirstUnlock: locked,
      session: session(locked: locked, meta: meta), nowMs: nowMs,
      clock: ServerClock(offsetMs: meta?.serverOffsetMs), calls: snapshot,
      unknownKidRecent: unknownKid.count, level: meta?.level ?? .full, placeholder: makeUUID(),
      room: { [roomFile] roomId in roomFile?.room == roomId ? roomFile : nil })
    let outcome = RingDecision.decide(input)
    if !locked, opened.isUnknownKey {
      unknownKid.append(received)
    }
    if outcome.disablePushTypes {
      registry?.desiredPushTypes = []
    }
    if outcome.reregister {
      queue("keyMismatch")
    }
    if case .generic(let ring) = outcome.action, ring.beforeFirstUnlock, let blob {
      keptBlobs[ring.uuid] = blob
    }
    calls.reportPush(outcome.action) { [weak self] report in
      completion()
      self?.finished(
        outcome, report: report, opened: opened, received: received, mustReport: mustReport)
    }
  }

  private func finished(
    _ outcome: RingOutcome, report: PushReport, opened: VoipBlobOpen, received: Date,
    mustReport: Bool?
  ) {
    var fields: [(String, String)] = [
      ("ms", String(Int(now().timeIntervalSince(received) * 1000))),
      ("must", mustReport.map { $0 ? "1" : "0" } ?? "-"),
    ]
    if case .opened(_, let ring) = opened {
      fields.append(("lag", String(Int64(received.timeIntervalSince1970 * 1000) - ring.ts)))
      if let token = cache.roomToken(ring.room) {
        fields.append(("t", String(token.prefix(8))))
      }
    }
    cache.log?.append(outcome.log, fields)
    guard case .shown(let uuid) = report else {
      if case .generic(let ring) = outcome.action { keptBlobs[ring.uuid] = nil }
      return
    }
    var roomId: String?
    if case .opened(_, let ring) = opened { roomId = ring.room }
    onReported(RingReported(uuid: uuid, roomId: roomId))
    if outcome.prewarm {
      prewarm()
    }
  }

  @objc func protectedDataBecameAvailable() {
    let kept = keptBlobs
    guard !kept.isEmpty else { return }
    keptBlobs = [:]
    let nowMs = Int64(now().timeIntervalSince1970 * 1000)
    guard case .ready(let voipKeys) = keys.load() else {
      for uuid in kept.keys { calls.endUnbound(uuid: uuid) }
      return
    }
    let level = cache.meta()?.level ?? .full
    for (uuid, blob) in kept {
      switch VoipBlob.open(blob, key: { voipKeys.key(for: $0, nowMs: nowMs) }) {
      case .opened(let header, let ring):
        let identity = CallIdentity.uuid(roomId: ring.room, callId: ring.call)
        let clock = ServerClock(offsetMs: cache.meta()?.serverOffsetMs)
        if clock.isStale(expirySeconds: header.expiry, deviceMs: nowMs, atLeast: ring.ts)
          || cache.ledger().isResolved(identity) || ring.caller == cache.meta()?.user
          || ring.kind == .canary
        {
          calls.endUnbound(uuid: uuid)
          continue
        }
        let name = CallerName.display(level: level, room: cache.room(ring.room), ring: ring)
        if calls.bind(
          uuid: uuid, roomId: ring.room, callId: ring.call, callerId: ring.caller, name: name,
          isVideo: ring.kind == .video)
        {
          prewarm()
        }
      case .unknownKid, .unknownVersion:
        calls.treatAsGeneric(uuid: uuid)
        queue("keyMismatch")
        prewarm()
      case .forged:
        calls.endUnbound(uuid: uuid)
      }
    }
  }

  private func session(locked: Bool, meta: NotifyMeta?) -> RingSession {
    if locked { return .signedIn(userId: "") }
    if cache.signedOut() == .present { return .signedOut }
    guard let meta else { return .noSession }
    return .signedIn(userId: meta.user)
  }

  private func queue(_ event: String) {
    guard !pendingEvents.contains(event) else { return }
    pendingEvents.append(event)
  }
}

extension VoipBlobOpen {
  var isUnknownKey: Bool {
    switch self {
    case .unknownKid, .unknownVersion: return true
    case .opened, .forged: return false
    }
  }
}

extension PushRingHandler: @preconcurrency PKPushRegistryDelegate {
  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType
  ) {
    guard type == .voIP else { return }
    tokenUpdated(pushCredentials.token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    tokenInvalidated()
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType, completion: @escaping @Sendable () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    handle(payload: payload.dictionaryPayload, mustReport: nil, completion: completion)
  }

  @available(iOS 26.4, *)
  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingVoIPPushWith payload: PKPushPayload,
    metadata: PKVoIPPushMetadata, withCompletionHandler completion: @escaping @Sendable () -> Void
  ) {
    handle(
      payload: payload.dictionaryPayload, mustReport: metadata.mustReport, completion: completion)
  }
}
