@preconcurrency import Flutter
import Foundation

@MainActor
final class AppLanguagePlugin: NSObject, @preconcurrency FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/locale", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AppLanguagePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "resolved" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(L10n.appLocale)
  }
}
