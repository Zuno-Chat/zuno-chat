import Foundation
import UIKit

@MainActor
final class NotifySweep: NSObject {
  static let shared = NotifySweep()
  static let markerName = "zuno-install-v1"

  static func markerURL() -> URL? {
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
      .appendingPathComponent(markerName, isDirectory: false)
  }

  @discardableResult
  static func run(marker: URL, backend: any KeychainBackend) -> Bool {
    do {
      _ = try Data(contentsOf: marker)
      return false
    } catch CocoaError.fileReadNoSuchFile {
    } catch {
      return false
    }
    let written = FileManager.default.createFile(
      atPath: marker.path, contents: Data([0x31]),
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    guard written else {
      NSLog("zuno/sweep: the install marker was not written; the notify and VoIP keys stay")
      return false
    }
    var excluded = marker
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? excluded.setResourceValues(values)
    _ = backend.delete(service: NotifyKeychain.service, accessGroup: nil)
    _ = backend.delete(service: VoipKeyStore.service, accessGroup: nil)
    return true
  }

  func runWhenProtectedDataAvailable() {
    guard UIApplication.shared.isProtectedDataAvailable else {
      NotificationCenter.default.addObserver(
        self, selector: #selector(protectedDataBecameAvailable),
        name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
      return
    }
    sweep()
  }

  @objc private func protectedDataBecameAvailable() {
    NotificationCenter.default.removeObserver(
      self, name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    sweep()
  }

  private func sweep() {
    guard let marker = Self.markerURL() else { return }
    Self.run(marker: marker, backend: SystemKeychain())
  }
}
