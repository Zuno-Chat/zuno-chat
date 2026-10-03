import Foundation
import UserNotifications

enum NseContentFactory {
  static let messageTone = "message_tone.caf"
  static let fallbackRing = "fallback_ring.caf"
  static let silentRing = "silent_ring.caf"

  static func content(for delivery: NseDelivery, original: UNNotificationContent)
    -> UNNotificationContent
  {
    guard !delivery.usesOriginal else { return original }
    let content =
      (original.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
    content.userInfo = delivery.userInfo
    content.threadIdentifier = delivery.threadId
    content.categoryIdentifier = NotificationCategories.shown(delivery.category)
    if let badge = delivery.badge { content.badge = NSNumber(value: badge) }
    content.title = delivery.title
    content.subtitle = ""
    content.body = delivery.body
    content.sound = sound(delivery.sound, original: original.sound)
    switch delivery.interruption {
    case .active: content.interruptionLevel = .active
    case .passive: content.interruptionLevel = .passive
    case .timeSensitive: content.interruptionLevel = .timeSensitive
    }
    return content
  }

  static func sound(_ sound: NseDelivery.Sound, original: UNNotificationSound?)
    -> UNNotificationSound?
  {
    switch sound {
    case .none: return nil
    case .original: return original
    case .messageTone: return UNNotificationSound(named: UNNotificationSoundName(messageTone))
    case .ring: return UNNotificationSound(named: UNNotificationSoundName(fallbackRing))
    case .silentRing: return UNNotificationSound(named: UNNotificationSoundName(silentRing))
    }
  }

  static func delivered(_ notification: UNNotification) -> NseDelivered {
    let content = notification.request.content
    var info: [String: String] = [:]
    for key in ["t", "e", "o", "k", "f", "rg"] {
      if let value = content.userInfo[key] as? String { info[key] = value }
    }
    var payloadEventId: String?
    if let payload = content.userInfo["payload"] as? String,
      let json = NseJson.parse(Data(payload.utf8))
    {
      payloadEventId = json["eventId"]?.string
    }
    return NseDelivered(
      identifier: notification.request.identifier,
      dateMs: Int64(notification.date.timeIntervalSince1970 * 1000), title: content.title,
      body: content.body, threadId: content.threadIdentifier, userInfo: info,
      payloadEventId: payloadEventId,
      pushed: notification.request.trigger is UNPushNotificationTrigger
        || CatchUpComposer.isCatchUp(notification.request.identifier))
  }
}

final class NseContentSink: @unchecked Sendable {
  private let lock = NSLock()
  private let original: UNNotificationContent
  private let remove: @Sendable ([String]) -> Void
  private var handler: ((UNNotificationContent) -> Void)?
  private var best: NseDelivery = .passthrough

  init(
    original: UNNotificationContent, remove: @escaping @Sendable ([String]) -> Void,
    handler: @escaping (UNNotificationContent) -> Void
  ) {
    self.original = original
    self.remove = remove
    self.handler = handler
  }

  func offer(_ delivery: NseDelivery) {
    lock.lock()
    best = delivery
    lock.unlock()
  }

  func finish(_ delivery: NseDelivery?) {
    lock.lock()
    guard let handler else {
      lock.unlock()
      return
    }
    self.handler = nil
    let chosen = delivery ?? best
    lock.unlock()
    if !chosen.removals.isEmpty { remove(chosen.removals) }
    handler(NseContentFactory.content(for: chosen, original: original))
  }
}
