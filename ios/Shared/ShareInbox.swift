import Foundation
import UniformTypeIdentifiers

enum ShareInbox {
  static let appGroupKey = "ZunoAppGroup"
  static let launchURL = URL(string: "im.zuno.chat://share")!
  static let freshness: TimeInterval = 10 * 60
  static let manifestName = "manifest.json"

  static func isLaunch(_ url: URL) -> Bool {
    url.scheme == launchURL.scheme && url.host == launchURL.host
  }

  static func root(bundle: Bundle = .main) -> URL? {
    guard let group = bundle.object(forInfoDictionaryKey: appGroupKey) as? String,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return container.appendingPathComponent("ShareInbox", isDirectory: true)
  }

  static func sweep(_ root: URL, now: Date) -> [ShareInboxEntry] {
    var fresh: [ShareInboxEntry] = []
    for directory in entries(in: root) {
      guard let manifest = manifest(in: directory) else {
        if !isFresh(created(directory) ?? .distantPast, now: now) {
          try? FileManager.default.removeItem(at: directory)
        }
        continue
      }
      if isFresh(manifest.created, now: now) {
        fresh.append(ShareInboxEntry(directory: directory, manifest: manifest))
      } else {
        try? FileManager.default.removeItem(at: directory)
      }
    }
    return fresh
  }

  static func entries(in directory: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.creationDateKey], options: []))
      ?? []
  }

  static func created(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
  }

  private static func isFresh(_ created: Date, now: Date) -> Bool {
    abs(now.timeIntervalSince(created)) <= freshness
  }

  private static func manifest(in directory: URL) -> ShareManifest? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent(manifestName))
    else { return nil }
    return try? ShareManifest.decoded(from: data)
  }
}

struct ShareInboxEntry: Sendable {
  let directory: URL
  let manifest: ShareManifest
}

struct ShareManifest: Codable, Equatable, Sendable {
  struct File: Codable, Equatable, Sendable {
    var path: String
    var name: String
    var mimeType: String?
  }

  var created: Date
  var text: String?
  var files: [File]

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return try encoder.encode(self)
  }

  static func decoded(from data: Data) throws -> ShareManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(ShareManifest.self, from: data)
  }
}

enum ShareFileName {
  static func safe(_ name: String) -> String {
    let cleaned = name.replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\\", with: "_")
    return ["", ".", ".."].contains(cleaned) ? "shared" : cleaned
  }

  static func named(_ suggested: String?, typeIdentifier: String) -> String {
    let name = safe((suggested ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    guard (name as NSString).pathExtension.isEmpty,
      let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension
    else { return name }
    return "\(name).\(fileExtension)"
  }

  static func mimeType(name: String, typeIdentifier: String) -> String? {
    let fileExtension = (name as NSString).pathExtension
    if !fileExtension.isEmpty,
      let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType
    {
      return mimeType
    }
    return UTType(typeIdentifier)?.preferredMIMEType
  }
}

enum ShareItemKind: Equatable, Sendable {
  case file(String)
  case fileURL
  case link
  case text
  case unsupported

  private static let skipped: Set<String> = [
    "com.apple.live-photo", "com.apple.live-photo-bundle", "com.apple.webarchive",
  ]

  static func of(_ identifiers: [String]) -> ShareItemKind {
    let types = identifiers.compactMap { identifier -> (identifier: String, type: UTType)? in
      guard !skipped.contains(identifier), let type = UTType(identifier) else { return nil }
      return (identifier, type)
    }
    let isContent = { (type: UTType) in type.conforms(to: .data) && !type.conforms(to: .url) }
    if types.contains(where: { $0.type.conforms(to: .fileURL) }) {
      if let content = types.first(where: { isContent($0.type) }) {
        return .file(content.identifier)
      }
      return .fileURL
    }
    if let media = types.first(where: {
      $0.type.conforms(to: .image) || $0.type.conforms(to: .audiovisualContent)
    }) {
      return .file(media.identifier)
    }
    if types.contains(where: { $0.type.conforms(to: .url) }) { return .link }
    if types.contains(where: { $0.type.conforms(to: .plainText) }) { return .text }
    if let other = types.first(where: { isContent($0.type) }) { return .file(other.identifier) }
    return .unsupported
  }
}

struct ShareEntry {
  let directory: URL
  private(set) var files: [ShareManifest.File] = []
  private(set) var texts: [String] = []

  static func create(in root: URL, id: String = UUID().uuidString) throws -> ShareEntry {
    let files = FileManager.default
    if !files.fileExists(atPath: root.path) {
      try files.createDirectory(at: root, withIntermediateDirectories: true)
      var excluded = root
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? excluded.setResourceValues(values)
    }
    let directory = root.appendingPathComponent(id, isDirectory: true)
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    return ShareEntry(directory: directory)
  }

  static func place(
    _ source: URL, in directory: URL, index: Int, typeIdentifier: String
  ) throws -> ShareManifest.File {
    guard (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else {
      throw CocoaError(.featureUnsupported)
    }
    let name = ShareFileName.named(source.lastPathComponent, typeIdentifier: typeIdentifier)
    let target = try slot(index, in: directory).appendingPathComponent(name)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.copyItem(at: source, to: target)
    return file(index: index, name: name, typeIdentifier: typeIdentifier)
  }

  static func place(
    _ data: Data, named suggested: String, in directory: URL, index: Int, typeIdentifier: String
  ) throws -> ShareManifest.File {
    let name = ShareFileName.named(suggested, typeIdentifier: typeIdentifier)
    let target = try slot(index, in: directory).appendingPathComponent(name)
    try data.write(to: target)
    return file(index: index, name: name, typeIdentifier: typeIdentifier)
  }

  mutating func add(_ file: ShareManifest.File) {
    files.append(file)
  }

  mutating func add(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !texts.contains(text)
    else { return }
    texts.append(text)
  }

  func commit(created: Date) throws -> Bool {
    let text = texts.isEmpty ? nil : texts.joined(separator: "\n")
    guard text != nil || !files.isEmpty else {
      discard()
      return false
    }
    let manifest = ShareManifest(created: created, text: text, files: files)
    try manifest.encoded().write(
      to: directory.appendingPathComponent(ShareInbox.manifestName), options: .atomic)
    return true
  }

  func discard() {
    try? FileManager.default.removeItem(at: directory)
  }

  private static func slot(_ index: Int, in directory: URL) throws -> URL {
    let slot = directory.appendingPathComponent(String(index), isDirectory: true)
    if !FileManager.default.fileExists(atPath: slot.path) {
      try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: false)
    }
    return slot
  }

  private static func file(index: Int, name: String, typeIdentifier: String)
    -> ShareManifest.File
  {
    ShareManifest.File(
      path: "\(index)/\(name)", name: name,
      mimeType: ShareFileName.mimeType(name: name, typeIdentifier: typeIdentifier))
  }
}

struct SharePayload: Equatable, Sendable {
  struct File: Equatable, Sendable {
    var uri: String
    var name: String
    var mimeType: String?
  }

  var text: String?
  var files: [File]
}

struct ShareInboxCollector {
  static let importLifetime: TimeInterval = 24 * 60 * 60

  let inbox: URL
  let imports: URL

  func collect(now: Date) -> SharePayload? {
    let fresh = ShareInbox.sweep(inbox, now: now)
    guard let newest = fresh.max(by: { $0.manifest.created < $1.manifest.created }) else {
      return nil
    }
    for older in fresh where older.directory != newest.directory {
      try? FileManager.default.removeItem(at: older.directory)
    }
    prune(now: now)
    let target = imports.appendingPathComponent(
      newest.directory.lastPathComponent, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.moveItem(at: newest.directory, to: target)
    } catch {
      return nil
    }
    return SharePayload(
      text: newest.manifest.text,
      files: newest.manifest.files.map { file in
        SharePayload.File(
          uri: target.appendingPathComponent(file.path).absoluteString, name: file.name,
          mimeType: file.mimeType)
      })
  }

  private func prune(now: Date) {
    for directory in ShareInbox.entries(in: imports)
    where now.timeIntervalSince(ShareInbox.created(directory) ?? .distantPast)
      > Self.importLifetime
    {
      try? FileManager.default.removeItem(at: directory)
    }
  }
}
