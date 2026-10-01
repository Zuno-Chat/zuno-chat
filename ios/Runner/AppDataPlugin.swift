@preconcurrency import Flutter
import UIKit

@MainActor
final class AppDataPlugin: NSObject, @preconcurrency FlutterPlugin {
  private nonisolated static let databaseSidecars = ["", "-wal", "-shm", "-journal"]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/app_data", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AppDataPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "wipe" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let keep = (call.arguments as? [String: Any])?["keep"] as? [String], !keep.isEmpty
    else {
      result(false)
      return
    }
    Task {
      let wiped = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: Self.wipe(keeping: keep))
        }
      }
      result(wiped)
    }
  }

  private nonisolated static func wipe(keeping databases: [String]) -> Bool {
    let files = FileManager.default
    let kept = Set(
      databases.flatMap { path in
        databaseSidecars.map { URL(fileURLWithPath: path + $0).standardizedFileURL.path }
      })
    var wiped = true

    func empty(_ directory: URL?, required: Bool = true) {
      guard let directory,
        let items = try? files.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil, options: [])
      else { return }
      for item in items {
        let name = item.lastPathComponent
        if name.hasPrefix("com.apple.") || name.hasPrefix(".com.apple.")
          || kept.contains(item.standardizedFileURL.path)
        {
          continue
        }
        do {
          try files.removeItem(at: item)
        } catch {
          if required { wiped = false }
        }
      }
    }

    empty(files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
    empty(files.urls(for: .documentDirectory, in: .userDomainMask).first)
    empty(files.urls(for: .cachesDirectory, in: .userDomainMask).first)
    empty(files.temporaryDirectory)
    empty(ShareInbox.root(), required: false)
    let library = files.urls(for: .libraryDirectory, in: .userDomainMask).first
    empty(library?.appendingPathComponent("SplashBoard/Snapshots"), required: false)
    empty(library?.appendingPathComponent("Saved Application State"), required: false)
    if let domain = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: domain)
    }
    return wiped
  }
}
