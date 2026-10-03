import Foundation
import MetricKit

struct MetricSummary: Codable, Equatable, Sendable {
  let kind: String
  let endMs: Int64
  let counts: [String: Int]

  var channelValue: [String: Any] { ["kind": kind, "end_ms": endMs, "counts": counts] }

  var line: String {
    ([kind] + counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }).joined(separator: " ")
  }
}

enum MetricSummaries {
  static func make(kind: String, end: Date, counts: [String: Int]) -> MetricSummary? {
    let kept = counts.filter { $0.value > 0 }
    guard !kept.isEmpty else { return nil }
    return MetricSummary(
      kind: kind, endMs: Int64((end.timeIntervalSince1970 * 1000).rounded()), counts: kept)
  }

  static func crashKey(terminationReason: String?) -> String? {
    guard let reason = terminationReason?.lowercased() else { return nil }
    if reason.contains("baadca11") { return "pushkit_unreported" }
    if reason.contains("dead10cc") { return "locked_file" }
    if reason.contains("8badf00d") { return "watchdog" }
    return nil
  }

  static func exits(from payload: MXMetricPayload) -> MetricSummary? {
    guard let exits = payload.applicationExitMetrics?.backgroundExitData else { return nil }
    return make(
      kind: "exits", end: payload.timeStampEnd,
      counts: [
        "locked_file": exits.cumulativeSuspendedWithLockedFileExitCount,
        "memory": exits.cumulativeMemoryResourceLimitExitCount
          + exits.cumulativeMemoryPressureExitCount,
        "watchdog": exits.cumulativeAppWatchdogExitCount,
        "task_timeout": exits.cumulativeBackgroundTaskAssertionTimeoutExitCount,
        "cpu": exits.cumulativeCPUResourceLimitExitCount,
        "bad_access": exits.cumulativeBadAccessExitCount
          + exits.cumulativeIllegalInstructionExitCount,
        "abnormal": exits.cumulativeAbnormalExitCount,
      ])
  }

  static func crashes(from payload: MXDiagnosticPayload) -> MetricSummary? {
    var counts: [String: Int] = [:]
    for crash in payload.crashDiagnostics ?? [] {
      counts[crashKey(terminationReason: crash.terminationReason) ?? "abnormal", default: 0] += 1
    }
    return make(kind: "crash", end: payload.timeStampEnd, counts: counts)
  }
}

final class MetricSummaryStore: @unchecked Sendable {
  static let capacity = 20
  static let standard = MetricSummaryStore(
    url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("zuno-metrics.json"))

  private let url: URL
  private let lock = NSLock()

  init(url: URL) {
    self.url = url
  }

  func append(_ summaries: [MetricSummary]) {
    guard !summaries.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    save(Array((load() + summaries).suffix(Self.capacity)))
  }

  func recent() -> [MetricSummary] {
    lock.lock()
    defer { lock.unlock() }
    return load()
  }

  private func load() -> [MetricSummary] {
    guard let data = try? Data(contentsOf: url),
      let stored = try? JSONDecoder().decode([MetricSummary].self, from: data)
    else { return [] }
    return stored
  }

  private func save(_ summaries: [MetricSummary]) {
    guard let data = try? JSONEncoder().encode(summaries) else { return }
    try? data.write(to: url, options: .atomic)
  }
}
