@preconcurrency import Flutter
import UIKit

@MainActor
final class AppDataPlugin: NSObject, @preconcurrency FlutterPlugin {
  private nonisolated static let databaseSidecars = ["", "-wal", "-shm", "-journal"]

  private let signOut: @MainActor () -> Bool
  private let emptyFiles: @Sendable ([String]) -> Bool

  init(
    signOut: @escaping @MainActor () -> Bool = { PushRingHandler.shared.signOut() },
    emptyFiles: @escaping @Sendable ([String]) -> Bool = { AppDataPlugin.wipe(keeping: $0) }
  ) {
    self.signOut = signOut
    self.emptyFiles = emptyFiles
  }

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
    let signedOut = signOut()
    let emptyFiles = self.emptyFiles
    Task {
      let emptied = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: emptyFiles(keep))
        }
      }
      result(signedOut && emptied)
    }
  }

  nonisolated static func wipe(keeping databases: [String]) -> Bool {
    let files = FileManager.default
    let library = files.urls(for: .libraryDirectory, in: .userDomainMask).first
    let wiped = empty(
      required: [
        files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        files.urls(for: .documentDirectory, in: .userDomainMask).first,
        files.urls(for: .cachesDirectory, in: .userDomainMask).first,
        files.temporaryDirectory,
      ],
      optional: [
        ShareInbox.root(), library?.appendingPathComponent("SplashBoard/Snapshots"),
        library?.appendingPathComponent("Saved Application State"),
      ],
      keeping: databases)
    if let domain = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: domain)
    }
    return wiped
  }

  nonisolated static func empty(required: [URL?], optional: [URL?], keeping databases: [String])
    -> Bool
  {
    let files = FileManager.default
    let kept = Set(
      databases.flatMap { path in
        databaseSidecars.map { URL(fileURLWithPath: path + $0).standardizedFileURL.path }
      })
    var wiped = true

    func clear(_ directory: URL?, required: Bool) {
      guard let directory else { return }
      let items: [URL]
      do {
        items = try files.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil, options: [])
      } catch CocoaError.fileReadNoSuchFile {
        return
      } catch {
        if required { wiped = false }
        return
      }
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

    for directory in required { clear(directory, required: true) }
    for directory in optional { clear(directory, required: false) }
    return wiped
  }
}
