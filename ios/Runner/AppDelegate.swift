import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "ZunoApnsPlugin") {
      ApnsTokenPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoVideoToolsPlugin") {
      VideoToolsPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoImageResizerPlugin") {
      ImageResizerPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoAppDataPlugin") {
      AppDataPlugin.register(with: registrar)
    }
  }
}
