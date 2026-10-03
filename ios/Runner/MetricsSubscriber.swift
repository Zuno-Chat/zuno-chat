import Foundation
import MetricKit

enum MetricKitLine {
  static let voipKillCode = "0xbaadca11"

  static func line(terminationReason: String?, exceptionType: Int?, signal: Int?) -> String {
    let reason = (terminationReason ?? "").lowercased()
    let kind = reason.contains(voipKillCode) ? "voip_unreported" : "crash"
    var fields = [kind]
    if let exceptionType { fields.append("exception=\(exceptionType)") }
    if let signal { fields.append("signal=\(signal)") }
    if let code = reason.range(of: #"0x[0-9a-f]{8}"#, options: .regularExpression) {
      fields.append("code=\(reason[code])")
    }
    return fields.joined(separator: " ")
  }
}

final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
  static let shared = MetricsSubscriber(
    defaults: .standard,
    log: { line in
      Task { @MainActor in ReadModelCache.shared.log?.append("metrickit", [("summary", line)]) }
    })
  static let pendingKey = "zuno.metrics.pending"
  static let pendingLimit = 20

  private let defaults: UserDefaults
  private let log: @Sendable (String) -> Void
  private let lock = NSLock()
  private var memoryWatch: Task<Void, Never>?

  init(defaults: UserDefaults, log: @escaping @Sendable (String) -> Void) {
    self.defaults = defaults
    self.log = log
  }

  func start() {
    MXMetricManager.shared.add(self)
    guard memoryWatch == nil else { return }
    if #available(iOS 27.0, *) {
      memoryWatch = Task.detached { [weak self] in
        for await report in MetricManager().diagnosticReports {
          guard case .memoryException = report.result else { continue }
          let key =
            report.environment.bundleIdentifier.hasSuffix(".NotificationService")
            ? "extension_memory" : "memory"
          guard
            let summary = MetricSummaries.make(
              kind: "memory", end: report.timeRange.end, counts: [key: 1])
          else { continue }
          MetricSummaryStore.standard.append([summary])
          self?.record([summary.line])
        }
      }
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    let lines = payloads.flatMap { payload in
      (payload.crashDiagnostics ?? []).map {
        MetricKitLine.line(
          terminationReason: $0.terminationReason, exceptionType: $0.exceptionType?.intValue,
          signal: $0.signal?.intValue)
      }
    }
    record(lines)
    MetricSummaryStore.standard.append(payloads.compactMap(MetricSummaries.crashes(from:)))
  }

  func didReceive(_ payloads: [MXMetricPayload]) {
    let summaries = payloads.compactMap(MetricSummaries.exits(from:))
    MetricSummaryStore.standard.append(summaries)
    record(summaries.map(\.line))
  }

  func record(_ lines: [String]) {
    guard !lines.isEmpty else { return }
    lock.lock()
    let pending = (defaults.stringArray(forKey: Self.pendingKey) ?? []) + lines
    defaults.set(Array(pending.suffix(Self.pendingLimit)), forKey: Self.pendingKey)
    lock.unlock()
    for line in lines { log(line) }
  }

  func takePending() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    let pending = defaults.stringArray(forKey: Self.pendingKey) ?? []
    defaults.removeObject(forKey: Self.pendingKey)
    return pending
  }
}
