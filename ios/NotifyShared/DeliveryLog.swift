import Foundation

struct DeliveryLog: Sendable {
  static let maxLines = 200

  let url: URL

  func append(_ event: String, _ fields: [(String, String)] = [], at date: Date = Date()) {
    var line = Self.timestamp(date) + " " + Self.clean(event)
    for (key, value) in fields {
      line += " \(Self.clean(key))=\(Self.clean(value))"
    }
    line += "\n"
    let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard descriptor >= 0 else {
      let failure = POSIXError.current
      if failure.code != .EPERM { CaughtErrors.record("delivery log open", failure) }
      return
    }
    let bytes = Array(line.utf8)
    let written = bytes.withUnsafeBufferPointer {
      Darwin.write(descriptor, $0.baseAddress, $0.count)
    }
    if written < 0 { CaughtErrors.record("delivery log write", POSIXError.current) }
    close(descriptor)
    trim()
  }

  func lines() -> [String] {
    let text: String
    do {
      text = try String(contentsOf: url, encoding: .utf8)
    } catch CocoaError.fileReadNoSuchFile {
      return []
    } catch CocoaError.fileReadNoPermission {
      return []
    } catch {
      CaughtErrors.record("delivery log read", error)
      return []
    }
    return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  }

  static func timestamp(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }

  private static func clean(_ text: String) -> String {
    String(text.map { $0.isWhitespace || $0.isNewline ? "_" : $0 })
  }

  private func trim() {
    let kept = lines()
    guard kept.count > Self.maxLines else { return }
    let text = kept.suffix(Self.maxLines).joined(separator: "\n") + "\n"
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    do {
      try Data(text.utf8).write(to: temporary)
    } catch {
      CaughtErrors.record("delivery log trim", error)
      return
    }
    if rename(temporary.path, url.path) != 0 {
      CaughtErrors.record("delivery log trim rename", POSIXError.current)
      try? FileManager.default.removeItem(at: temporary)
    }
  }
}
