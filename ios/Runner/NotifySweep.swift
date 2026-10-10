import Foundation

@MainActor
enum NotifySweep {
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
      CaughtErrors.record("sweep marker read", error)
      return false
    }
    do {
      try Data([0x31]).write(
        to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } catch {
      CaughtErrors.record("sweep marker write", error)
      return false
    }
    var excluded = marker
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    CaughtErrors.attempt("sweep marker exclude backup") { try excluded.setResourceValues(values) }
    _ = backend.delete(service: NotifyKeychain.service, accessGroup: nil)
    _ = backend.delete(service: VoipKeyStore.service, accessGroup: nil)
    return true
  }

  static func sweepWhenProtectedDataAvailable() {
    ProtectedDataGate.shared.run {
      guard let marker = markerURL() else { return }
      run(marker: marker, backend: SystemKeychain())
    }
  }
}
