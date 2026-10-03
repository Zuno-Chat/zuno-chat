@preconcurrency import Flutter
import Foundation

@MainActor
final class LaunchPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let host: EngineHost
  private let diagnostics: MetricsSubscriber

  init(host: EngineHost = .shared, diagnostics: MetricsSubscriber = .shared) {
    self.host = host
    self.diagnostics = diagnostics
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/launch", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LaunchPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takeWakeReason":
      result(host.takeWakeReason())
    case "takeDiagnostics":
      result(diagnostics.takePending())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
