@preconcurrency import Flutter
import UIKit

@MainActor
final class EngineHost {
  enum Reason: String, Sendable {
    case scene
    case ring
    case action
  }

  typealias Launch = @MainActor (_ arguments: [String], _ headless: Bool) -> FlutterEngine

  static let shared = EngineHost(
    launch: EngineHost.launchAndRegister, canStart: ProtectedData.isAvailable)

  private let launch: Launch
  private let canStart: @MainActor () -> Bool
  private(set) var engine: FlutterEngine?
  private var wakeReason: Reason?
  private var waitingWindows: [UIWindow] = []

  init(launch: @escaping Launch, canStart: @escaping @MainActor () -> Bool) {
    self.launch = launch
    self.canStart = canStart
  }

  nonisolated static func arguments(for reason: Reason) -> [String] {
    reason == .scene ? [] : ["--zuno-wake=\(reason.rawValue)"]
  }

  func start(_ reason: Reason) -> FlutterEngine {
    if let engine { return engine }
    let engine = launch(Self.arguments(for: reason), reason != .scene)
    self.engine = engine
    if reason != .scene { wakeReason = reason }
    return engine
  }

  func startForRing() {
    guard engine == nil, canStart() else { return }
    _ = start(.ring)
  }

  func takeWakeReason() -> String? {
    defer { wakeReason = nil }
    return wakeReason?.rawValue
  }

  func rootViewController(for window: UIWindow) -> UIViewController {
    if engine != nil || canStart() {
      return FlutterViewController(engine: start(.scene), nibName: nil, bundle: nil)
    }
    waitingWindows.append(window)
    NotificationCenter.default.addObserver(
      self, selector: #selector(protectedDataBecameAvailable),
      name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    return UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
      ?? UIViewController()
  }

  @objc private func protectedDataBecameAvailable() {
    let windows = waitingWindows
    waitingWindows = []
    NotificationCenter.default.removeObserver(
      self, name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    for window in windows where window.windowScene != nil {
      window.rootViewController = FlutterViewController(
        engine: start(.scene), nibName: nil, bundle: nil)
    }
  }

  static func launchAndRegister(arguments: [String], headless: Bool) -> FlutterEngine {
    let engine = FlutterEngine(name: "io.flutter", project: nil, allowHeadlessExecution: true)
    engine.run(withEntrypoint: nil, libraryURI: nil, initialRoute: nil, entrypointArgs: arguments)
    registerPlugins(engine)
    if headless {
      engine.lifecycleChannel.sendMessage("AppLifecycleState.paused")
    }
    return engine
  }

  static func registerPlugins(_ engine: FlutterEngine) {
    GeneratedPluginRegistrant.register(with: engine)
    CallKitCenter.shared.audio.adoptRegisteredWebRTC()
    let plugins: [(key: String, type: any FlutterPlugin.Type)] = [
      ("ZunoApnsPlugin", ApnsTokenPlugin.self),
      ("ZunoPushDiagPlugin", PushDiagPlugin.self),
      ("ZunoVideoToolsPlugin", VideoToolsPlugin.self),
      ("ZunoImageResizerPlugin", ImageResizerPlugin.self),
      ("ZunoAppDataPlugin", AppDataPlugin.self),
      ("ZunoCallsChannelPlugin", CallsChannelPlugin.self),
      ("ZunoUploadServicePlugin", UploadServicePlugin.self),
      ("ZunoRoomLaunchPlugin", RoomLaunchPlugin.self),
      ("ZunoNotificationActionsPlugin", NotificationActionsPlugin.self),
      ("ZunoShareInboxPlugin", ShareInboxPlugin.self),
      ("ZunoWakeLockPlugin", WakeLockPlugin.self),
      ("ZunoClientLeasePlugin", ClientLeasePlugin.self),
      ("ZunoVoipPlugin", VoipPlugin.self),
      ("ZunoLaunchPlugin", LaunchPlugin.self),
      ("ZunoErrorsPlugin", ErrorsPlugin.self),
      ("ZunoNsePlugin", NsePlugin.self),
      ("ZunoLiveLocationPlugin", LiveLocationPlugin.self),
    ]
    for plugin in plugins {
      if let registrar = engine.registrar(forPlugin: plugin.key) {
        plugin.type.register(with: registrar)
      }
    }
    if let registrar = engine.registrar(forPlugin: "ZunoNetworkPlugin") {
      NetworkPlugin.register(with: registrar)
    }
  }
}

@MainActor
enum ProtectedData {
  static func isAvailable() -> Bool {
    switch VoipKeyStore().load() {
    case .locked: return false
    case .ready: return true
    case .missing, .unavailable: return UIApplication.shared.isProtectedDataAvailable
    }
  }
}
