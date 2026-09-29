@preconcurrency import Flutter
import UIKit

@MainActor
final class ApnsTokenPlugin: NSObject, @preconcurrency FlutterPlugin {
  private static let tokenTimeoutNanos: UInt64 = 30 * NSEC_PER_SEC

  private var pending: [FlutterResult] = []
  private var timeout: Task<Void, Never>?

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
    timeout = Task { [weak self] in
      try? await Task.sleep(nanoseconds: Self.tokenTimeoutNanos)
      guard !Task.isCancelled else { return }
      self?.finish(
        FlutterError(code: "timeout", message: "APNs gave no device token", details: nil))
    }
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
