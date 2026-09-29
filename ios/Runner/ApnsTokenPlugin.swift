import Flutter
import UIKit

final class ApnsTokenPlugin: NSObject, FlutterPlugin {
  private static let tokenTimeout: TimeInterval = 30

  private var pending: [FlutterResult] = []
  private var timeout: DispatchWorkItem?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ApnsTokenPlugin()
    let channel = FlutterMethodChannel(name: "zuno/apns", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getToken" else {
      result(FlutterMethodNotImplemented)
      return
    }
    pending.append(result)
    guard pending.count == 1 else { return }
    let timeout = DispatchWorkItem { [weak self] in
      self?.finish(
        FlutterError(code: "timeout", message: "APNs gave no device token", details: nil))
    }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.tokenTimeout, execute: timeout)
    UIApplication.shared.registerForRemoteNotifications()
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    finish(deviceToken.map { String(format: "%02x", $0) }.joined())
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    finish(
      FlutterError(
        code: "registration_failed", message: error.localizedDescription, details: nil))
  }

  private func finish(_ reply: Any) {
    timeout?.cancel()
    timeout = nil
    let results = pending
    pending = []
    for result in results { result(reply) }
  }
}
