@preconcurrency import Flutter
import Foundation

@MainActor
final class NsePlugin: NSObject, @preconcurrency FlutterPlugin {
  private let cache: ReadModelCache

  init(cache: ReadModelCache = .shared) {
    self.cache = cache
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/nse", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NsePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let roomId = args?["room_id"] as? String
    let json = (args?["json"] as? String).map { Data($0.utf8) }
    switch call.method {
    case "threadKey":
      guard let roomId else { return result(badArguments("room_id")) }
      result(cache.threadKey(roomId: roomId))
    case "writeMeta":
      guard let json else { return result(badArguments("json")) }
      result(write { try cache.writeMeta(json) })
    case "writeRoom":
      guard let roomId, let json else { return result(badArguments("room_id and json")) }
      result(write { try cache.writeRoom(roomId: roomId, json: json) })
    case "deleteRoom":
      guard let roomId else { return result(badArguments("room_id")) }
      cache.deleteRoom(roomId: roomId)
      result(nil)
    case "wipe":
      cache.wipe()
      result(nil)
    default:
      if NseAppMethods.handle(call, result: result) { return }
      result(FlutterMethodNotImplemented)
    }
  }

  private func write(_ body: () throws -> Void) -> Any? {
    do {
      try body()
      return nil
    } catch {
      return FlutterError(code: "write_failed", message: "\(error)", details: nil)
    }
  }

  private func badArguments(_ what: String) -> FlutterError {
    FlutterError(code: "bad_args", message: "\(what) is required", details: nil)
  }
}
