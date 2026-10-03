import Foundation

enum DarwinHint: String, CaseIterable, Sendable {
  case ringChanged = "im.zuno.chat.ring.changed"
  case callsChanged = "im.zuno.chat.calls.changed"
  case readModelChanged = "im.zuno.chat.readmodel.changed"

  func post() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue as CFString), nil,
      nil, true)
  }
}

final class DarwinHintCenter: @unchecked Sendable {
  static let shared = DarwinHintCenter()

  private let lock = NSLock()
  private var handlers: [String: [UUID: @Sendable () -> Void]] = [:]

  @discardableResult
  func observe(_ hint: DarwinHint, _ handler: @escaping @Sendable () -> Void) -> UUID {
    let token = UUID()
    lock.lock()
    let first = handlers[hint.rawValue] == nil
    handlers[hint.rawValue, default: [:]][token] = handler
    lock.unlock()
    if first {
      CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
        { _, observer, name, _, _ in
          guard let observer, let name else { return }
          let center = Unmanaged<DarwinHintCenter>.fromOpaque(observer).takeUnretainedValue()
          center.deliver(name.rawValue as String)
        }, hint.rawValue as CFString, nil, .deliverImmediately)
    }
    return token
  }

  func remove(_ token: UUID) {
    lock.lock()
    for name in handlers.keys {
      handlers[name]?[token] = nil
    }
    lock.unlock()
  }

  private func deliver(_ name: String) {
    lock.lock()
    let current = Array((handlers[name] ?? [:]).values)
    lock.unlock()
    for handler in current {
      handler()
    }
  }
}
