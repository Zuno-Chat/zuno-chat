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
    guard descriptor >= 0 else { return }
    let bytes = Array(line.utf8)
    _ = bytes.withUnsafeBufferPointer { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    close(descriptor)
    trim()
  }

  func lines() -> [String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
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
    guard (try? Data(text.utf8).write(to: temporary)) != nil else { return }
    if rename(temporary.path, url.path) != 0 {
      try? FileManager.default.removeItem(at: temporary)
    }
  }
}
