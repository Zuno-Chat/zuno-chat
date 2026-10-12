import Flutter
import UIKit

// shortcut: CallKit's Video button and a redial open Zuno with an INStart*CallIntent user activity nothing handles, handle it (camera on, room token back to its room) before turning Recents on
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let windowScene = scene as? UIWindowScene {
      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = EngineHost.shared.rootViewController(for: window)
      self.window = window
      window.makeKeyAndVisible()
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
