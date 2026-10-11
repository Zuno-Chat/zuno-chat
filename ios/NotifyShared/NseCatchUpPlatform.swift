import Foundation
@preconcurrency import UserNotifications
import os

final class NseCatchUpPlatform: CatchUpPlatform {
  struct Sources {
    let roomToken: (String) -> String?
    let eventToken: (String) -> String?
    let alreadyShown: (String) -> Bool
    let claim: (String) -> Bool
    let release: (String) -> Void
    let settle: (String) -> Void
    let render: (MissedEvent, Bool) -> CatchUpRender
  }

  private let sources: Sources
  private let memory: () -> Int
  private let center: () -> UNUserNotificationCenter

  init(
    sources: Sources, memory: @escaping () -> Int = { Int(os_proc_available_memory()) },
    center: @escaping () -> UNUserNotificationCenter = { .current() }
  ) {
    self.sources = sources
    self.memory = memory
    self.center = center
  }

  func roomToken(_ roomId: String) -> String? { sources.roomToken(roomId) }
  func eventToken(_ eventId: String) -> String? { sources.eventToken(eventId) }
  func alreadyShown(_ eventToken: String) -> Bool { sources.alreadyShown(eventToken) }
  func availableMemory() -> Int { memory() }

  func render(_ event: MissedEvent, decrypt: Bool) -> CatchUpRender {
    sources.render(event, decrypt)
  }

  func delivered() async -> [DeliveredNote] {
    await center().deliveredNotifications().map(DeliveredNote.init)
  }

  func remove(_ identifiers: [String]) {
    center().removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func post(_ request: UNNotificationRequest) async -> Bool {
    do {
      try await center().add(request)
      return true
    } catch {
      NotificationFailure.record("nse catch-up post", error)
      return false
    }
  }

  func claim(_ eventToken: String) -> Bool { sources.claim(eventToken) }
  func release(_ eventToken: String) { sources.release(eventToken) }
  func settle(_ eventToken: String) { sources.settle(eventToken) }
  func now() -> Date { Date() }
}
