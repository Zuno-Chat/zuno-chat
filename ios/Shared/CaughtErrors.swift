import CryptoKit
import Foundation
import os

struct CaughtError: Codable, Equatable, Sendable {
  let label: String
  let process: String
  let type: String
  let message: String
  let domain: String
  let code: Int
}

final class CaughtErrors: Sendable {
  static let directoryName = "zuno-caught"
  static let groupKeys = ["ZunoNotifyGroup", "ZunoAppGroup"]
  static let limit = 20
  static let messageLimit = 500
  static let chainLimit = 8
  static let settleSeconds: TimeInterval = 60
  static let shared = CaughtErrors(
    directory: directories()[0], process: process(bundleIdentifier: Bundle.main.bundleIdentifier))
  private static let lock = NSLock()
  private static let log = Logger(subsystem: "im.zuno.chat", category: "caught")

  let directory: URL
  let process: String

  init(directory: URL, process: String) {
    self.directory = directory
    self.process = process
  }

  static func process(bundleIdentifier: String?) -> String {
    let identifier = bundleIdentifier ?? ""
    if identifier.hasSuffix(".NotificationService") { return "nse" }
    if identifier.hasSuffix(".ShareExtension") { return "share" }
    return "app"
  }

  static func directories(bundle: Bundle = .main) -> [URL] {
    let groups = groupKeys.compactMap { key -> URL? in
      guard let group = bundle.object(forInfoDictionaryKey: key) as? String,
        !group.isEmpty, !group.contains("$("),
        let container = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: group)
      else { return nil }
      return container.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
    return (groups.isEmpty ? [URL.applicationSupportDirectory] : groups).map {
      $0.appendingPathComponent(directoryName, isDirectory: true)
    }
  }

  static func fileName(process: String, label: String) -> String {
    let digest = SHA256.hash(data: Data(label.utf8)).prefix(8)
    return "\(process)-\(digest.map { String(format: "%02x", $0) }.joined()).json"
  }

  static func message(_ error: any Error) -> String {
    let bridged = error as NSError
    guard !bridged.userInfo.isEmpty else {
      return String(String(describing: error).prefix(messageLimit))
    }
    let chain = sequence(first: bridged) { $0.userInfo[NSUnderlyingErrorKey] as? NSError }
      .dropFirst().prefix(chainLimit).map { "underlying \($0.domain) \($0.code)" }
    return String(
      ([bridged.localizedDescription] + chain).joined(separator: "; ").prefix(messageLimit))
  }

  static func record(_ label: String, _ error: any Error) {
    shared.record(label, error)
  }

  @discardableResult
  static func attempt<T>(_ label: String, _ body: () throws -> T) -> T? {
    shared.attempt(label, body)
  }

  static func takeAll(bundle: Bundle = .main) -> [CaughtError] {
    takeAll(from: directories(bundle: bundle))
  }

  static func takeAll(from directories: [URL]) -> [CaughtError] {
    lock.withLock { directories.flatMap { drain($0, now: Date()) } }
  }

  func record(_ label: String, _ error: any Error) {
    let bridged = error as NSError
    let message = Self.message(error)
    Self.log.error("\(label, privacy: .public): \(message, privacy: .private)")
    let entry = CaughtError(
      label: label, process: process, type: String(reflecting: Swift.type(of: error)),
      message: message, domain: bridged.domain, code: bridged.code)
    Self.lock.withLock { write(entry) }
  }

  @discardableResult
  func attempt<T>(_ label: String, _ body: () throws -> T) -> T? {
    do {
      return try body()
    } catch {
      record(label, error)
      return nil
    }
  }

  func take() -> [CaughtError] {
    Self.takeAll(from: [directory])
  }

  private func write(_ entry: CaughtError) {
    let target = directory.appendingPathComponent(
      Self.fileName(process: process, label: entry.label))
    guard !FileManager.default.fileExists(atPath: target.path), waiting() < Self.limit else {
      return
    }
    do {
      try prepare()
      try JSONEncoder().encode(entry).write(
        to: target,
        options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
    } catch CocoaError.fileWriteFileExists {
    } catch {
      Self.log.error("caught journal write: \(String(describing: error), privacy: .private)")
    }
  }

  private func waiting() -> Int {
    Self.names(in: directory).count(where: { $0.hasPrefix("\(process)-") })
  }

  private func prepare() throws {
    guard !FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try excluded.setResourceValues(values)
    } catch {
      Self.log.error(
        "caught journal exclude backup: \(String(describing: error), privacy: .private)")
    }
  }

  private static func names(in directory: URL) -> [String] {
    do {
      return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    } catch CocoaError.fileReadNoSuchFile {
      return []
    } catch {
      log.error("caught journal list: \(String(describing: error), privacy: .private)")
      return []
    }
  }

  private static func drain(_ directory: URL, now: Date) -> [CaughtError] {
    names(in: directory).sorted().compactMap { name in
      let url = directory.appendingPathComponent(name)
      let data: Data
      do {
        data = try Data(contentsOf: url)
      } catch CocoaError.fileReadNoPermission {
        return nil
      } catch {
        remove(url)
        return nil
      }
      do {
        let entry = try JSONDecoder().decode(CaughtError.self, from: data)
        remove(url)
        return entry
      } catch {
        if !settling(url, now: now) { remove(url) }
        return nil
      }
    }
  }

  private static func settling(_ url: URL, now: Date) -> Bool {
    do {
      let modified = try url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      return modified.map { now.timeIntervalSince($0) < settleSeconds } ?? false
    } catch {
      return false
    }
  }

  private static func remove(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch CocoaError.fileNoSuchFile {
    } catch {
      log.error("caught journal remove: \(String(describing: error), privacy: .private)")
    }
  }
}
