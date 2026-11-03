import Foundation
import MetricKit

enum MetricKitLine {
  static func line(terminationReason: String?, exceptionType: Int?, signal: Int?) -> String {
    let reason = (terminationReason ?? "").lowercased()
    let unreported = MetricSummaries.pushkitUnreported
    var fields = [
      MetricSummaries.crashKey(terminationReason: reason) == unreported ? unreported : "crash"
    ]
    if let exceptionType { fields.append("exception=\(exceptionType)") }
    if let signal { fields.append("signal=\(signal)") }
    if let code = reason.range(of: #"0x[0-9a-f]{8}"#, options: .regularExpression) {
      fields.append("code=\(reason[code])")
    }
    return fields.joined(separator: " ")
  }

  static func report(terminationReason: String?, exceptionType: Int?, signal: Int?)
    -> MetricReport
  {
    let cause =
      MetricSummaries.crashKey(terminationReason: terminationReason)
      ?? signal.map { "signal=\($0)" }
      ?? exceptionType.map { "exception=\($0)" }
      ?? "unknown"
    return MetricReport(
      source: "crash", reason: cause,
      summary: line(
        terminationReason: terminationReason, exceptionType: exceptionType, signal: signal))
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
          self?.record(summary.reports)
        }
      }
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    let reports = payloads.flatMap { payload in
      (payload.crashDiagnostics ?? []).map {
        MetricKitLine.report(
          terminationReason: $0.terminationReason, exceptionType: $0.exceptionType?.intValue,
          signal: $0.signal?.intValue)
      }
    }
    record(reports)
    MetricSummaryStore.standard.append(payloads.compactMap(MetricSummaries.crashes(from:)))
  }

  func didReceive(_ payloads: [MXMetricPayload]) {
    let summaries = payloads.compactMap(MetricSummaries.exits(from:))
    MetricSummaryStore.standard.append(summaries)
    record(summaries.flatMap(\.reports))
  }

  func record(_ reports: [MetricReport]) {
    guard !reports.isEmpty else { return }
    lock.lock()
    let pending = Array((loadPending() + reports).suffix(Self.pendingLimit))
    CaughtErrors.attempt("metric reports write") {
      defaults.set(try JSONEncoder().encode(pending), forKey: Self.pendingKey)
    }
    lock.unlock()
    for report in reports { log(report.summary) }
  }

  func takePending() -> [MetricReport] {
    lock.lock()
    defer { lock.unlock() }
    let pending = loadPending()
    defaults.removeObject(forKey: Self.pendingKey)
    return pending
  }

  private func loadPending() -> [MetricReport] {
    guard let data = defaults.data(forKey: Self.pendingKey) else { return [] }
    return CaughtErrors.attempt("metric reports read") {
      try JSONDecoder().decode([MetricReport].self, from: data)
    } ?? []
  }
}
