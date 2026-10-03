import CryptoKit
import Foundation

enum SealedRead: Equatable, Sendable {
  case found(Data)
  case missing
  case unreadable
  case corrupt
}

enum MarkerRead: Equatable, Sendable {
  case present
  case absent
  case unreadable
}

struct NotifyStore: Sendable {
  static let groupInfoKey = "ZunoNotifyGroup"
  static let directoryName = "zuno-nse"

  let directory: URL

  init(directory: URL) {
    self.directory = directory
  }

  static func groupIdentifier(bundle: Bundle = .main) -> String? {
    guard let group = bundle.object(forInfoDictionaryKey: groupInfoKey) as? String,
      !group.isEmpty, !group.contains("$(")
    else { return nil }
    return group
  }

  static func shared(bundle: Bundle = .main) -> NotifyStore? {
    guard let group = groupIdentifier(bundle: bundle),
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return NotifyStore(
      directory:
        container
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true))
  }

  func prepare() throws {
    let files = FileManager.default
    try files.createDirectory(
      at: directory.appendingPathComponent("rooms", isDirectory: true),
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    try? files.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: directory.path)
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? excluded.setResourceValues(values)
  }

  func read(_ name: String, key: SymmetricKey) -> SealedRead {
    let data: Data
    do {
      data = try Data(contentsOf: url(name))
    } catch CocoaError.fileReadNoSuchFile {
      return .missing
    } catch {
      return .unreadable
    }
    guard let plaintext = try? SealedFile.open(data, name: name, key: key) else { return .corrupt }
    return .found(plaintext)
  }

  func write(_ name: String, plaintext: Data, key: SymmetricKey) throws {
    try place(
      try SealedFile.seal(plaintext, name: name, key: key), at: url(name),
      protection: .completeUntilFirstUserAuthentication)
  }

  @discardableResult
  func writeIfChanged(_ name: String, plaintext: Data, key: SymmetricKey) throws -> Bool {
    if case .found(let current) = read(name, key: key), current == plaintext { return false }
    try write(name, plaintext: plaintext, key: key)
    return true
  }

  func remove(_ name: String) {
    try? FileManager.default.removeItem(at: url(name))
  }

  func wipe() {
    let files = FileManager.default
    guard
      let items = try? files.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [])
    else { return }
    for item in items where item.lastPathComponent != NotifyFile.signedOut {
      try? files.removeItem(at: item)
    }
    try? files.createDirectory(
      at: directory.appendingPathComponent("rooms", isDirectory: true),
      withIntermediateDirectories: true)
  }

  func writeRingFlag(_ ringtoneOn: Bool) throws {
    try place(Data([ringtoneOn ? 0x31 : 0x30]), at: url(NotifyFile.ringFlag), protection: .none)
  }

  func readRingFlag() -> Bool? {
    guard let data = try? Data(contentsOf: url(NotifyFile.ringFlag)), data.count == 1 else {
      return nil
    }
    switch data[data.startIndex] {
    case 0x31: return true
    case 0x30: return false
    default: return nil
    }
  }

  func markSignedOut() throws {
    try place(
      Data([0x31]), at: url(NotifyFile.signedOut),
      protection: .completeUntilFirstUserAuthentication)
  }

  func clearSignedOut() {
    remove(NotifyFile.signedOut)
  }

  func signedOut() -> MarkerRead {
    do {
      _ = try Data(contentsOf: url(NotifyFile.signedOut))
      return .present
    } catch CocoaError.fileReadNoSuchFile {
      return .absent
    } catch {
      return .unreadable
    }
  }

  func url(_ name: String) -> URL {
    directory.appendingPathComponent(name, isDirectory: false)
  }

  private func place(_ data: Data, at target: URL, protection: FileProtectionType) throws {
    let folder = target.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
    let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    let written = data.withUnsafeBytes { buffer in
      Darwin.write(descriptor, buffer.baseAddress, buffer.count)
    }
    let synced = fsync(descriptor)
    close(descriptor)
    guard written == data.count, synced == 0 else {
      try? FileManager.default.removeItem(at: temporary)
      throw CocoaError(.fileWriteUnknown)
    }
    try? FileManager.default.setAttributes(
      [.protectionKey: protection], ofItemAtPath: temporary.path)
    guard rename(temporary.path, target.path) == 0 else {
      try? FileManager.default.removeItem(at: temporary)
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
