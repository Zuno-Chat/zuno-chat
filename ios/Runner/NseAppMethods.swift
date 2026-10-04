@preconcurrency import Flutter
import UserNotifications

enum NseAppRequest: Sendable {
  case writeShown([String])
  case takeMarks
  case readOutcomes
  case setCredential(String?, Int64?)
  case syncBadge([String])

  init?(method: String, arguments: Any?) {
    let fields = arguments as? [String: Any] ?? [:]
    switch method {
    case "writeShown": self = .writeShown(fields["e"] as? [String] ?? [])
    case "takeMarks": self = .takeMarks
    case "readOutcomes": self = .readOutcomes
    case "setCredential":
      self = .setCredential(
        fields["credential"] as? String, (fields["expires_ts"] as? NSNumber)?.int64Value)
    case "syncBadge": self = .syncBadge(fields["unread"] as? [String] ?? [])
    default: return nil
    }
  }

  func perform() async -> UncheckedSendable<Any?> {
    switch self {
    case .writeShown(let keys):
      NseAppStore.current()?.writeShown(keys)
      return UncheckedSendable(nil)
    case .takeMarks:
      return UncheckedSendable(NseAppStore.current()?.takeMarks(.standard) ?? [])
    case .readOutcomes:
      let suite = NotifyStore.groupIdentifier().flatMap { UserDefaults(suiteName: $0) }
      let now = Int64(Date().timeIntervalSince1970 * 1000)
      return UncheckedSendable(
        NseAppStore.current()?.readOutcomes(.standard, counters: suite, nowMs: now) ?? [])
    case .setCredential(let credential, let expiresMs):
      let stored = await MainActor.run {
        NseAppStore.setCredential(credential, expiresMs: expiresMs)
      }
      return UncheckedSendable(stored)
    case .syncBadge(let unread):
      let count = NseAppLogic.badge(unread: unread, delivered: await LiveNseCenter().delivered())
      NseBadge.apply(count)
      return UncheckedSendable(count)
    }
  }
}

@MainActor
enum NseAppMethods {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    guard let request = NseAppRequest(method: call.method, arguments: call.arguments) else {
      return false
    }
    let reply = UncheckedSendable(result)
    Task.detached(priority: .utility) {
      let value = await request.perform()
      await MainActor.run { reply.value(value.value) }
    }
    return true
  }
}

enum NseBadge {
  static func apply(_ count: Int) {
    UNUserNotificationCenter.current().setBadgeCount(count)
  }
}

@MainActor
final class NseAppHooks {
  static let shared = NseAppHooks()

  private var observer: UUID?

  func start(rings: PushRingHandler = .shared) {
    guard observer == nil else { return }
    observer = DarwinHintCenter.shared.observe(.callsChanged) {
      Task { @MainActor in NseAppHooks.shared.endSummarizedRings() }
    }
    rings.onReported = { ring in
      Task.detached { _ = await NseAppHooks.sweep(after: ring) }
    }
  }

  nonisolated static func sweep(
    after ring: RingReported,
    hashing: NseHashing? = NseLive.secrets().map { LiveNseHashing(key: $0.tokenKey) },
    center: NseDeliveredCenter = LiveNseCenter()
  ) async -> [String] {
    await RingFloorSweeper.sweep(
      roomId: ring.roomId, callUuid: ring.uuid, hashing: hashing, center: center,
      remove: {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0)
      },
      nowMs: Int64(Date().timeIntervalSince1970 * 1000))
  }

  func endSummarizedRings(calls: CallKitCenter = .shared, defaults: UserDefaults = .standard) {
    guard let store = NseAppStore.current() else { return }
    let taken = Int64(defaults.double(forKey: NseAppStore.ringsEndedKey))
    let (ends, pointer) = NseAppLogic.ringEnds(store.state.marks(), after: taken)
    defaults.set(Double(pointer), forKey: NseAppStore.ringsEndedKey)
    for end in ends {
      calls.endIncoming(
        roomId: end.roomId, callId: end.callId,
        reason: end.declined ? .declinedElsewhere : .unanswered)
    }
  }
}
