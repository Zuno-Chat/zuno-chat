import UIKit

@MainActor
final class ProtectedDataGate: NSObject {
  static let shared = ProtectedDataGate()

  private var waiting: [@MainActor () -> Void] = []

  func run(_ work: @escaping @MainActor () -> Void) {
    guard !UIApplication.shared.isProtectedDataAvailable else { return work() }
    if waiting.isEmpty {
      NotificationCenter.default.addObserver(
        self, selector: #selector(protectedDataBecameAvailable),
        name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    }
    waiting.append(work)
  }

  @objc private func protectedDataBecameAvailable() {
    NotificationCenter.default.removeObserver(
      self, name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    let work = waiting
    waiting = []
    for item in work { item() }
  }
}
