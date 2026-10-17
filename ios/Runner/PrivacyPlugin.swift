@preconcurrency import Flutter
import UIKit
import UniformTypeIdentifiers

@MainActor
final class PrivacyPlugin: NSObject, @preconcurrency FlutterPlugin {
  private static let clipboardLifetime: TimeInterval = 90

  private var copiedChangeCount: Int?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/privacy", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PrivacyPlugin(), channel: channel)
    ScreenCover.shared.start()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "copySensitive":
      guard let text = args?["text"] as? String else {
        result(FlutterError(code: "bad_args", message: "text is required", details: nil))
        return
      }
      let pasteboard = UIPasteboard.general
      pasteboard.setItems(
        [[UTType.utf8PlainText.identifier: text]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(Self.clipboardLifetime),
        ])
      copiedChangeCount = pasteboard.changeCount
      result(nil)
    case "clearClipboardIfMatches":
      if copiedChangeCount == UIPasteboard.general.changeCount {
        UIPasteboard.general.items = []
      }
      copiedChangeCount = nil
      result(nil)
    case "setPreventScreenshots":
      ScreenCover.shared.hidesContent = args?["enabled"] as? Bool == true
      result(nil)
    case "setThirdPartyKeyboards":
      KeyboardPolicy.allowsThirdParty = args?["allowed"] as? Bool == true
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

@MainActor
enum KeyboardPolicy {
  static var allowsThirdParty = false

  static func allows(_ extensionPoint: UIApplication.ExtensionPointIdentifier) -> Bool {
    extensionPoint != .keyboard || allowsThirdParty
  }
}

@MainActor
final class ScreenCover: NSObject {
  static let shared = ScreenCover()

  weak var pictureInPicture: CallPictureInPicture? {
    didSet { pictureInPicture?.setConcealed(conceals) }
  }

  var hidesContent = false {
    didSet { updateAll() }
  }

  private var started = false
  private var inactive = Set<ObjectIdentifier>()
  private var covers: [ObjectIdentifier: (window: UIWindow, notice: UILabel)] = [:]
  private var captureObservations: [ObjectIdentifier: any UITraitChangeRegistration] = [:]

  private var windowScenes: [UIWindowScene] {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  }

  private var conceals: Bool {
    hidesContent && windowScenes.contains(where: Self.isCaptured)
  }

  func start() {
    guard !started else { return }
    started = true
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(sceneWillConnect(_:)),
      name: UIScene.willConnectNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidDisconnect(_:)),
      name: UIScene.didDisconnectNotification, object: nil)
    windowScenes.forEach(observeCapture)
  }

  private static func isCaptured(_ scene: UIWindowScene) -> Bool {
    scene.traitCollection.sceneCaptureState == .active
  }

  private func observeCapture(_ scene: UIWindowScene) {
    let key = ObjectIdentifier(scene)
    guard captureObservations[key] == nil else { return }
    captureObservations[key] = scene.registerForTraitChanges([UITraitSceneCaptureState.self]) {
      [weak self] (_: UIWindowScene, _: UITraitCollection) in
      self?.updateAll()
    }
  }

  @objc private func sceneWillConnect(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    observeCapture(scene)
  }

  @objc private func sceneWillDeactivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    observeCapture(scene)
    inactive.insert(ObjectIdentifier(scene))
    update(scene)
  }

  @objc private func sceneDidActivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    observeCapture(scene)
    inactive.remove(ObjectIdentifier(scene))
    update(scene)
  }

  @objc private func sceneDidDisconnect(_ notification: Notification) {
    guard let scene = notification.object as? UIScene else { return }
    let key = ObjectIdentifier(scene)
    inactive.remove(key)
    covers.removeValue(forKey: key)?.window.isHidden = true
    if let registration = captureObservations.removeValue(forKey: key),
      let windowScene = scene as? UIWindowScene
    {
      windowScene.unregisterForTraitChanges(registration)
    }
  }

  private func updateAll() {
    windowScenes.forEach(update)
    pictureInPicture?.setConcealed(conceals)
  }

  private func update(_ scene: UIWindowScene) {
    let key = ObjectIdentifier(scene)
    let captured = Self.isCaptured(scene)
    guard hidesContent, inactive.contains(key) || captured else {
      covers[key]?.window.isHidden = true
      return
    }
    let cover = covers[key] ?? makeCover(for: scene)
    covers[key] = cover
    cover.notice.isHidden = !captured
    cover.window.isHidden = false
  }

  private func makeCover(for scene: UIWindowScene) -> (window: UIWindow, notice: UILabel) {
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    let root =
      UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
      ?? UIViewController()
    let notice = UILabel()
    notice.text = L10n.callsScreenCaptureHidden
    notice.textColor = UIColor(red: 14 / 255, green: 17 / 255, blue: 22 / 255, alpha: 1)
    notice.font = .preferredFont(forTextStyle: .body)
    notice.adjustsFontForContentSizeCategory = true
    notice.numberOfLines = 0
    notice.textAlignment = .center
    notice.translatesAutoresizingMaskIntoConstraints = false
    root.view.addSubview(notice)
    let guide = root.view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      notice.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 32),
      notice.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -32),
      notice.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -48),
    ])
    window.rootViewController = root
    return (window, notice)
  }
}
