import ImageIO
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private enum Loaded: Sendable {
    case file(ShareManifest.File)
    case text(String)
  }

  private static let unreadable = "Could not read what was shared. Try again."
  private static let openLater = "Open Zuno in the next few minutes to finish sharing."

  private let spinner = UIActivityIndicatorView(style: .medium)
  private let message = UILabel()
  private let button = UIButton(type: .system)
  private var work: Task<Void, Never>?
  private var entry: ShareEntry?
  private var loads: [Progress] = []
  private var finished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    isModalInPresentation = true
    view.backgroundColor = .systemBackground
    spinner.startAnimating()
    message.text = "Preparing to share…"
    message.font = .preferredFont(forTextStyle: .body)
    message.adjustsFontForContentSizeCategory = true
    message.textAlignment = .center
    message.numberOfLines = 0
    button.setTitle("Cancel", for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.addTarget(self, action: #selector(cancel), for: .primaryActionTriggered)
    let stack = UIStackView(arrangedSubviews: [spinner, message, button])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
    ])
    work = Task { await share() }
  }

  private func share() async {
    guard let root = ShareInbox.root() else { return show(Self.unreadable) }
    _ = ShareInbox.sweep(root, now: Date())
    guard var entry = try? ShareEntry.create(in: root) else { return show(Self.unreadable) }
    self.entry = entry
    var index = 0
    for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
      var found = false
      for provider in item.attachments ?? [] {
        guard !Task.isCancelled else { return }
        switch await load(provider, index: index, into: entry.directory) {
        case .file(let file):
          entry.add(file)
          found = true
        case .text(let text):
          entry.add(text)
          found = true
        case nil:
          break
        }
        index += 1
      }
      if !found, let text = item.attributedContentText?.string {
        entry.add(text)
      }
    }
    guard !Task.isCancelled else { return }
    self.entry = nil
    button.isEnabled = false
    let committed: Bool
    do {
      committed = try entry.commit(created: Date())
    } catch {
      entry.discard()
      committed = false
    }
    guard committed else { return show(Self.unreadable) }
    if await openZuno() {
      finish { $0.completeRequest(returningItems: nil) }
    } else {
      show(Self.openLater)
    }
  }

  private func load(_ provider: NSItemProvider, index: Int, into directory: URL) async
    -> Loaded?
  {
    switch ShareItemKind.of(provider.registeredTypeIdentifiers) {
    case .file(let type):
      if let file = await copyFile(provider, type: type, index: index, into: directory) {
        return .file(file)
      }
      guard UTType(type)?.conforms(to: .image) == true else { return nil }
      return await writeImage(provider, type: type, index: index, into: directory)
    case .fileURL:
      return await loadURL(provider, type: UTType.fileURL.identifier, index: index, into: directory)
    case .link:
      return await loadURL(provider, type: UTType.url.identifier, index: index, into: directory)
    case .text:
      return await loadText(provider)
    case .unsupported:
      return nil
    }
  }

  private func copyFile(_ provider: NSItemProvider, type: String, index: Int, into directory: URL)
    async -> ShareManifest.File?
  {
    await withCheckedContinuation { continuation in
      loads.append(
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
          continuation.resume(
            returning: url.flatMap {
              try? ShareEntry.place($0, in: directory, index: index, typeIdentifier: type)
            })
        })
    }
  }

  private func writeImage(_ provider: NSItemProvider, type: String, index: Int, into directory: URL)
    async -> Loaded?
  {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
        let file: ShareManifest.File? =
          switch item {
          case let url as URL where url.isFileURL:
            try? ShareEntry.place(url, in: directory, index: index, typeIdentifier: type)
          case let data as Data:
            try? ShareEntry.place(
              data, named: "shared", in: directory, index: index,
              typeIdentifier: Self.imageType(of: data) ?? type)
          case let image as UIImage:
            image.pngData().flatMap {
              try? ShareEntry.place(
                $0, named: "shared", in: directory, index: index,
                typeIdentifier: UTType.png.identifier)
            }
          default:
            nil
          }
        continuation.resume(returning: file.map { .file($0) })
      }
    }
  }

  private func loadURL(_ provider: NSItemProvider, type: String, index: Int, into directory: URL)
    async -> Loaded?
  {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
        if let text = item as? String {
          return continuation.resume(returning: .text(text))
        }
        let url =
          (item as? URL)
          ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
        guard let url else { return continuation.resume(returning: nil) }
        guard url.isFileURL else {
          return continuation.resume(returning: .text(url.absoluteString))
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let contentType =
          (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? .data
        let file = try? ShareEntry.place(
          url, in: directory, index: index, typeIdentifier: contentType.identifier)
        continuation.resume(returning: file.map { .file($0) })
      }
    }
  }

  private func loadText(_ provider: NSItemProvider) async -> Loaded? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
        let text: String? =
          switch item {
          case let string as String: string
          case let attributed as NSAttributedString: attributed.string
          case let data as Data: String(data: data, encoding: .utf8)
          default: nil
          }
        continuation.resume(returning: text.map { .text($0) })
      }
    }
  }

  private nonisolated static func imageType(of data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceGetType(source) as String?
  }

  private func openZuno() async -> Bool {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        return await application.open(ShareInbox.launchURL)
      }
      responder = current.next
    }
    return false
  }

  private func show(_ text: String) {
    spinner.stopAnimating()
    spinner.isHidden = true
    message.text = text
    button.setTitle("Close", for: .normal)
    button.removeTarget(self, action: #selector(cancel), for: .primaryActionTriggered)
    button.addTarget(self, action: #selector(close), for: .primaryActionTriggered)
    button.isEnabled = true
  }

  private func finish(_ end: (NSExtensionContext) -> Void) {
    guard !finished, let context = extensionContext else { return }
    finished = true
    end(context)
  }

  @objc private func cancel() {
    work?.cancel()
    for load in loads { load.cancel() }
    entry?.discard()
    entry = nil
    finish { $0.cancelRequest(withError: CocoaError(.userCancelled)) }
  }

  @objc private func close() {
    finish { $0.completeRequest(returningItems: nil) }
  }
}
