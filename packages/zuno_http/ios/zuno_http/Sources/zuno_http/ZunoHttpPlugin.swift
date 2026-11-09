import Flutter
import Foundation

public final class ZunoHttpPlugin: NSObject, FlutterPlugin {
  private let http = HttpBridge()
  private let sockets = WebSocketBridge()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let plugin = ZunoHttpPlugin()
    let httpChannel = FlutterMethodChannel(
      name: "zuno/http", binaryMessenger: messenger,
      codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?())
    httpChannel.setMethodCallHandler { [http = plugin.http] call, result in
      http.handle(call, result: result)
    }
    let socketChannel = FlutterMethodChannel(
      name: "zuno/websocket", binaryMessenger: messenger,
      codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?())
    socketChannel.setMethodCallHandler { [sockets = plugin.sockets] call, result in
      sockets.handle(call, result: result)
    }
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    http.cancelAll()
    sockets.cancelAll()
  }
}
