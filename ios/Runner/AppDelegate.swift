import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, @preconcurrency FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func excludeAppDataFromBackup() {
    let files = FileManager.default
    for directory in [
      FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory,
    ] {
      guard var url = files.urls(for: directory, in: .userDomainMask).first else { continue }
      try? files.createDirectory(at: url, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
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
    if let registrar = registry.registrar(forPlugin: "ZunoCallsChannelPlugin") {
      CallsChannelPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoUploadServicePlugin") {
      UploadServicePlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoNetworkPlugin") {
      NetworkPlugin.register(with: registrar)
    }
  }
}
