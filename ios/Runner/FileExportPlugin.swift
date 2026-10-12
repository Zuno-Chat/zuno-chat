@preconcurrency import Flutter
import UIKit

@MainActor
final class FileExportPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let export: FileExport

  private init(registrar: FlutterPluginRegistrar) {
    export = FileExport { [weak registrar] in registrar?.viewController }
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/files", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FileExportPlugin(registrar: registrar), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "exportSensitiveFile":
      guard let name = args?["name"] as? String,
        let bytes = args?["bytes"] as? FlutterStandardTypedData
      else {
        result(
          FlutterError(code: "bad_args", message: "name and bytes are required", details: nil))
        return
      }
      export.present(name: name, data: bytes.data, done: result)
    case "exportFile":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path is required", details: nil))
        return
      }
      export.present(file: URL(fileURLWithPath: path), done: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

enum TemporaryLeftovers {
  static func found(in temporary: URL) -> [URL] {
    let files = FileManager.default
    let topLevel =
      (try? files.contentsOfDirectory(
        at: temporary, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
    let exports =
      (try? files.contentsOfDirectory(
        at: FileExport.root(in: temporary), includingPropertiesForKeys: nil,
        options: [])) ?? []
    return topLevel.filter { item in
      (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
    } + exports
  }

  static func discard(_ leftovers: [URL]) {
    guard !leftovers.isEmpty else { return }
    DispatchQueue.global(qos: .utility).async {
      for leftover in leftovers {
        try? FileManager.default.removeItem(at: leftover)
      }
    }
  }
}

@MainActor
final class FileExport: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  nonisolated static func root(in temporary: URL) -> URL {
    temporary.appendingPathComponent("sensitive-export", isDirectory: true)
  }

  private let presenter: () -> UIViewController?
  private var pending: (written: URL?, done: FlutterResult)?

  init(presenter: @escaping () -> UIViewController?) {
    self.presenter = presenter
    super.init()
  }

  func present(name: String, data: Data, done: @escaping FlutterResult) {
    guard let top = presentable(done) else { return }
    let folder = Self.root(in: FileManager.default.temporaryDirectory)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent((name as NSString).lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: file, options: [.withoutOverwriting, .completeFileProtection])
    } catch {
      try? FileManager.default.removeItem(at: folder)
      done(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
      return
    }
    show(file, from: top, written: folder, done: done)
  }

  func present(file: URL, done: @escaping FlutterResult) {
    guard FileManager.default.isReadableFile(atPath: file.path) else {
      done(FlutterError(code: "no_file", message: "nothing to export", details: nil))
      return
    }
    guard let top = presentable(done) else { return }
    show(file, from: top, written: nil, done: done)
  }

  private func presentable(_ done: FlutterResult) -> UIViewController? {
    guard pending == nil else {
      done(false)
      return nil
    }
    guard var top = presenter() else {
      done(FlutterError(code: "no_window", message: "nothing to present from", details: nil))
      return nil
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  private func show(
    _ file: URL, from top: UIViewController, written: URL?, done: @escaping FlutterResult
  ) {
    let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    picker.delegate = self
    picker.presentationController?.delegate = self
    pending = (written, done)
    top.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    finish(saved: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(saved: false)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(saved: false)
  }

  private func finish(saved: Bool) {
    guard let pending else { return }
    self.pending = nil
    if let written = pending.written {
      try? FileManager.default.removeItem(at: written)
    }
    pending.done(saved)
  }
}
