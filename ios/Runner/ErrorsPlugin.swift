@preconcurrency import Flutter
import Foundation

@MainActor
final class ErrorsPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let diagnostics: MetricsSubscriber
  private let caught: () -> [CaughtError]

  init(
    diagnostics: MetricsSubscriber = .shared,
    caught: @escaping () -> [CaughtError] = { CaughtErrors.takeAll() }
  ) {
    self.diagnostics = diagnostics
    self.caught = caught
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/errors", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ErrorsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "take" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(Self.entries(reports: diagnostics.takePending(), caught: caught()))
  }

  static func entries(reports: [MetricReport], caught: [CaughtError]) -> [[String: Any]] {
    reports.map(\.channelValue)
      + caught.map {
        [
          "kind": "caught", "label": $0.label, "process": $0.process, "type": $0.type,
          "message": $0.message, "domain": $0.domain, "code": $0.code,
        ]
      }
  }
}
