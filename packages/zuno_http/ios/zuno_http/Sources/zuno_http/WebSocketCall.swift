import Flutter
import Foundation

private let maximumMessageSize = 16 * 1024 * 1024
private let upgradeTimeout: TimeInterval = 30

final class WebSocketCall: SessionTaskHandler, NativeCall {
  private let onFinished: (WebSocketCall) -> Void
  private let lock = NSLock()
  private var task: URLSessionWebSocketTask?
  private var connecting: FlutterResult?
  private var closedByDart = false
  private var completed = false
  private var failure: (String, String)?
  private var removed = false

  init(onFinished: @escaping (WebSocketCall) -> Void) {
    self.onFinished = onFinished
  }

  func connect(url: URL, headers: [String: String], result: @escaping FlutterResult) {
    var request = URLRequest(url: url, timeoutInterval: upgradeTimeout)
    request.setHeaders(headers)
    let started = SharedSession.shared.session.webSocketTask(with: request)
    started.maximumMessageSize = maximumMessageSize
    lock.lock()
    task = started
    connecting = result
    lock.unlock()
    SharedSession.shared.register(started, handler: self)
    started.resume()
  }

  func receive(_ result: @escaping FlutterResult) {
    lock.lock()
    let socket = task
    let closing = closedByDart
    let done = completed
    let failed = failure
    lock.unlock()
    guard let socket, !closing else {
      result(nil)
      remove()
      return
    }
    if done {
      if let failed {
        result(FlutterError(code: failed.0, message: failed.1, details: nil))
      } else {
        result(nil)
      }
      remove()
      return
    }
    socket.receive { outcome in
      switch outcome {
      case .success(.data(let data)):
        result(FlutterStandardTypedData(bytes: data))
      case .success:
        self.receive(result)
      case .failure(let error):
        if self.wasClosedByDart || socket.closeCode != .invalid {
          result(nil)
        } else {
          result(
            FlutterError(code: "connectionLost", message: failureDetail(of: error), details: nil))
        }
        self.remove()
      }
    }
  }

  func send(_ bytes: Data, result: @escaping FlutterResult) {
    lock.lock()
    let socket = closedByDart || completed ? nil : task
    lock.unlock()
    guard let socket else {
      result(false)
      return
    }
    socket.send(.data(bytes)) { error in result(error == nil) }
  }

  func cancel() {
    close()
  }

  func close() {
    lock.lock()
    closedByDart = true
    let socket = task
    lock.unlock()
    socket?.cancel(with: .normalClosure, reason: nil)
    remove()
  }

  func didOpen() {
    lock.lock()
    let waiting = connecting
    connecting = nil
    lock.unlock()
    waiting?(nil)
  }

  func didComplete(error: Error?) {
    lock.lock()
    completed = true
    let waiting = connecting
    connecting = nil
    let socket = task
    if waiting == nil, !closedByDart, socket?.closeCode == .invalid {
      failure = ("connectionLost", error.map(failureDetail(of:)) ?? "The connection dropped")
    }
    lock.unlock()
    guard let waiting else { return }
    if let status = (socket?.response as? HTTPURLResponse)?.statusCode, status != 101 {
      waiting(FlutterError(code: "upgrade", message: "HTTP \(status)", details: status))
    } else if let error {
      waiting(FlutterError(code: failureKind(of: error), message: failureDetail(of: error), details: nil))
    } else {
      waiting(FlutterError(code: "connectionLost", message: "Closed before opening", details: nil))
    }
    remove()
  }

  private var wasClosedByDart: Bool {
    lock.lock()
    defer { lock.unlock() }
    return closedByDart
  }

  private func remove() {
    lock.lock()
    let first = !removed
    removed = true
    lock.unlock()
    if first { onFinished(self) }
  }
}

final class WebSocketBridge {
  private let sockets = CallRegistry<WebSocketCall>()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let id = arguments["id"] as? Int ?? 0
    switch call.method {
    case "connect":
      guard let text = arguments["url"] as? String, let url = URL(string: text) else {
        result(FlutterError(code: "protocol", message: "Invalid URL", details: nil))
        return
      }
      let socket = WebSocketCall(onFinished: { [weak sockets] ended in
        sockets?.remove(id, ended)
      })
      sockets.replace(id, with: socket)
      socket.connect(
        url: url, headers: arguments["headers"] as? [String: String] ?? [:], result: result)
    case "receive":
      if let socket = sockets[id] { socket.receive(result) } else { result(nil) }
    case "send":
      let bytes = (arguments["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
      if let socket = sockets[id] { socket.send(bytes, result: result) } else { result(false) }
    case "close":
      sockets[id]?.close()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func cancelAll() {
    sockets.cancelAll()
  }
}
