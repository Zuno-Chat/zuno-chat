@preconcurrency import Flutter
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CallsChannelPlugin: NSObject, @preconcurrency FlutterPlugin {
  private static let clipboardLifetime: TimeInterval = 90

  private var copiedChangeCount: Int?
  private var hidesContent = false
  private var inactive = Set<ObjectIdentifier>()
  private var covers: [ObjectIdentifier: (window: UIWindow, notice: UILabel)] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/calls", binaryMessenger: registrar.messenger())
    let plugin = CallsChannelPlugin()
    registrar.addMethodCallDelegate(plugin, channel: channel)
    plugin.observeScenes()
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
      hidesContent = args?["enabled"] as? Bool == true
      updateAllScenes()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func observeScenes() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidDisconnect(_:)),
      name: UIScene.didDisconnectNotification, object: nil)
    center.addObserver(
      self, selector: #selector(captureDidChange(_:)),
      name: UIScreen.capturedDidChangeNotification, object: nil)
  }

  @objc private func sceneWillDeactivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    inactive.insert(ObjectIdentifier(scene))
    update(scene)
  }

  @objc private func sceneDidActivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    inactive.remove(ObjectIdentifier(scene))
    update(scene)
  }

  @objc private func sceneDidDisconnect(_ notification: Notification) {
    guard let scene = notification.object as? UIScene else { return }
    inactive.remove(ObjectIdentifier(scene))
    covers.removeValue(forKey: ObjectIdentifier(scene))?.window.isHidden = true
  }

  @objc private func captureDidChange(_ notification: Notification) {
    updateAllScenes()
  }

  private func updateAllScenes() {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      update(scene)
    }
  }

  private func update(_ scene: UIWindowScene) {
    let key = ObjectIdentifier(scene)
    let captured = scene.screen.isCaptured
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
    notice.text = "Zuno is hidden while the screen is recorded or shared."
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
