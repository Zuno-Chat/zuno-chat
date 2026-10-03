import Foundation
@preconcurrency import UserNotifications
import os

final class NseCatchUpPlatform: CatchUpPlatform {
  struct Sources {
    let roomToken: (String) -> String?
    let eventToken: (String) -> String?
    let alreadyShown: (String) -> Bool
    let recordShown: ([String]) -> Void
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
    await center().deliveredNotifications().map {
      DeliveredNote(
        identifier: $0.request.identifier, thread: $0.request.content.threadIdentifier,
        userInfo: $0.request.content.userInfo,
        pushed: $0.request.trigger is UNPushNotificationTrigger)
    }
  }

  func remove(_ identifiers: [String]) {
    center().removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func post(_ request: UNNotificationRequest) async -> Bool {
    do {
      try await center().add(request)
      return true
    } catch {
      return false
    }
  }

  func recordShown(_ eventTokens: [String]) { sources.recordShown(eventTokens) }
  func now() -> Date { Date() }
}
