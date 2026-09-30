@preconcurrency import Flutter
import UIKit

@MainActor
final class UploadServicePlugin: NSObject, @preconcurrency FlutterPlugin {
  private var task: UIBackgroundTaskIdentifier = .invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/upload_service", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(UploadServicePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      endTask()
      task = UIApplication.shared.beginBackgroundTask(withName: "Upload") { [weak self] in
        MainActor.assumeIsolated { self?.endTask() }
      }
      result(nil)
    case "update":
      result(nil)
    case "stop":
      endTask()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func endTask() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}
