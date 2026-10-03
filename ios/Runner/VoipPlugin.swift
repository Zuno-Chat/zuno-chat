@preconcurrency import Flutter
import Foundation

@MainActor
final class VoipPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let handler: PushRingHandler
  private let keys: VoipKeyStore
  private let environment: @MainActor () -> String
  private let callKitAvailable: @MainActor () -> Bool
  private let token: @MainActor () -> Data?
  private let now: @MainActor () -> Date

  init(
    handler: PushRingHandler = .shared, keys: VoipKeyStore = VoipKeyStore(),
    environment: @escaping @MainActor () -> String = { PushEnvironment.current.rawValue },
    callKitAvailable: @escaping @MainActor () -> Bool = { CallKitCenter.shared.isAvailable },
    token: @escaping @MainActor () -> Data? = { PushRingHandler.shared.token },
    now: @escaping @MainActor () -> Date = { Date() }
  ) {
    self.handler = handler
    self.keys = keys
    self.environment = environment
    self.callKitAvailable = callKitAvailable
    self.token = token
    self.now = now
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/voip", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(VoipPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      guard case .ready(let current) = keys.current() else { return result(keychainError()) }
      result([
        "token": token().map { $0.base64EncodedString() as Any } ?? NSNull(),
        "environment": environment(),
        "kid": Int(current.kid),
        "key": current.key.base64EncodedString(),
        "callkit": callKitAvailable(),
      ])
    case "rotateKey":
      guard let rotated = keys.rotate() else { return result(keychainError()) }
      result(["kid": Int(rotated.kid), "key": rotated.key.base64EncodedString()])
    case "ackKey":
      guard let kid = (args?["kid"] as? NSNumber)?.uint32Value else {
        return result(FlutterError(code: "bad_args", message: "kid is required", details: nil))
      }
      _ = keys.acknowledge(kid: kid, nowMs: Int64(now().timeIntervalSince1970 * 1000))
      result(nil)
    case "takeEvents":
      result(handler.takeEvents().map { ["type": $0] })
    case "setSession":
      guard let signedIn = args?["signedIn"] as? Bool else {
        return result(FlutterError(code: "bad_args", message: "signedIn is required", details: nil))
      }
      handler.setSignedIn(signedIn)
      result(nil)
    case "devExport":
      result(devExport())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func devExport() -> [String: Any]? {
    guard environment() == "development", let token = token(),
      case .ready(let current) = keys.load()
    else { return nil }
    return [
      "token": token.map { String(format: "%02x", $0) }.joined(),
      "kid": Int(current.kid),
      "key": current.key.base64EncodedString(),
      "environment": "development",
    ]
  }

  private func keychainError() -> FlutterError {
    FlutterError(code: "keychain", message: "the VoIP key is not readable yet", details: nil)
  }
}
