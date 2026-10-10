@preconcurrency import Flutter
import Foundation

@MainActor
final class LaunchPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let host: EngineHost

  init(host: EngineHost = .shared) {
    self.host = host
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
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
