@preconcurrency import Flutter
import UIKit

@MainActor
final class ShareInboxPlugin: NSObject, @preconcurrency FlutterPlugin {
  private static var state = LaunchHandoff<SharePayload>()
  private static weak var current: ShareInboxPlugin?
  private static var activation: NSObjectProtocol?

  private let channel: FlutterMethodChannel
  private let attachment: Int

  private init(channel: FlutterMethodChannel, attachment: Int) {
    self.channel = channel
    self.attachment = attachment
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    if activation == nil {
      ShareCache.standard?.clear()
      activation = NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { collect() }
      }
    }
    let channel = FlutterMethodChannel(
      name: "zuno/share", binaryMessenger: registrar.messenger())
    let instance = ShareInboxPlugin(channel: channel, attachment: state.attach())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
    registrar.publish(instance)
    current = instance
  }

  private static func collect() {
    guard let payload = ShareCache.standard?.collector?.collect(now: Date()),
      state.offer(payload), let plugin = current
    else { return }
    plugin.channel.invokeMethod("share", arguments: payload.channelValue)
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    Self.state.detach(attachment)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takeLaunchShare":
      Self.collect()
      result(Self.state.take(attachment)?.channelValue)
    case "copyToCache":
      guard let request = ShareCache.request(from: call.arguments), let cache = ShareCache.standard
      else {
        result(FlutterError(code: "bad_arguments", message: nil, details: nil))
        return
      }
      Task {
        let paths = await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: cache.move(uris: request.uris, names: request.names))
          }
        }
        result(paths.map { path -> Any in path ?? NSNull() })
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

extension ShareInboxPlugin: @preconcurrency FlutterSceneLifeCycleDelegate {
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) -> Bool {
    guard urlContexts.contains(where: { ShareInbox.isLaunch($0.url) }) else { return false }
    Self.collect()
    return true
  }
}

struct ShareCache: Sendable {
  let root: URL

  static var standard: ShareCache? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
      ShareCache(root: $0.appendingPathComponent("Share", isDirectory: true))
    }
  }

  static func request(from arguments: Any?) -> (uris: [String], names: [String])? {
    guard let arguments = arguments as? [String: Any],
      let uris = arguments["uris"] as? [String],
      let names = arguments["names"] as? [String]
    else { return nil }
    return (uris, names)
  }

  var imports: URL { root.appendingPathComponent("Imports", isDirectory: true) }

  var copies: URL { root.appendingPathComponent("Copies", isDirectory: true) }

  var collector: ShareInboxCollector? {
    ShareInbox.root().map { ShareInboxCollector(inbox: $0, imports: imports) }
  }

  func clear() {
    try? FileManager.default.removeItem(at: root)
  }

  func move(uris: [String], names: [String]) -> [String?] {
    let files = FileManager.default
    let importsPath = imports.resolvingSymlinksInPath().path + "/"
    let batch = copies.appendingPathComponent(UUID().uuidString, isDirectory: true)
    return uris.enumerated().map { index, uri in
      guard let source = URL(string: uri), source.isFileURL,
        source.resolvingSymlinksInPath().path.hasPrefix(importsPath)
      else { return nil }
      let slot = batch.appendingPathComponent(String(index), isDirectory: true)
      let target = slot.appendingPathComponent(
        ShareFileName.safe(index < names.count ? names[index] : "shared"))
      do {
        try files.createDirectory(at: slot, withIntermediateDirectories: true)
        try files.moveItem(at: source, to: target)
        return target.path
      } catch {
        return nil
      }
    }
  }
}

extension SharePayload {
  var channelValue: [String: Any] {
    var value: [String: Any] = [
      "files": files.map { file -> [String: Any] in
        var item: [String: Any] = ["uri": file.uri, "name": file.name]
        if let mimeType = file.mimeType { item["mimeType"] = mimeType }
        return item
      }
    ]
    if let text { value["text"] = text }
    return value
  }
}
