import Flutter
import Foundation

private let maxBufferedBytes = 4 * 64 * 1024
private let ended = FlutterError(code: "cancelled", message: "The request has ended", details: nil)

final class SessionCall: SessionTaskHandler, NativeCall {
  typealias TaskStarter = (URLRequest, SessionTaskHandler) -> SessionTask

  private let hasBody: Bool
  private let startTask: TaskStarter
  private let onFinished: (SessionCall) -> Void
  private let lock = NSLock()
  private var task: SessionTask?
  private var opening: FlutterResult?
  private var reading: FlutterResult?
  private var pulling: FlutterResult?
  private var chunks: [Data] = []
  private var bufferedBytes = 0
  private var suspended = false
  private var answered = false
  private var finished = false
  private var cancelled = false
  private var removed = false
  private var failure: FlutterError?
  private var networkProtocol: String?
  private var writer: BodyWriter?
  private var wantsBytes = false
  private var rewind: ((InputStream?) -> Void)?
  private var rewindTold = false

  init(
    hasBody: Bool,
    startTask: @escaping TaskStarter = { SharedSession.shared.dataTask(with: $0, handler: $1) },
    onFinished: @escaping (SessionCall) -> Void
  ) {
    self.hasBody = hasBody
    self.startTask = startTask
    self.onFinished = onFinished
  }

  func open(_ request: URLRequest, result: @escaping FlutterResult) {
    var request = request
    lock.lock()
    opening = result
    if hasBody {
      let body = newWriter()
      writer = body
      request.httpBodyStream = body.input
    }
    let started = startTask(request, self)
    task = started
    lock.unlock()
    started.resume()
  }

  func read(_ result: @escaping FlutterResult) {
    lock.lock()
    defer { lock.unlock() }
    if chunks.isEmpty && !finished {
      reading = result
      resumeIfRoom()
    } else {
      deliver(result)
    }
  }

  func pullBody(_ result: @escaping FlutterResult) {
    lock.lock()
    let accept = answerPull(result)
    lock.unlock()
    accept?()
  }

  func write(_ chunk: Data, last: Bool, result: @escaping FlutterResult) {
    lock.lock()
    writer?.write(chunk, last: last)
    let accept = answerPull(result)
    lock.unlock()
    accept?()
  }

  func cancel() {
    lock.lock()
    guard !cancelled else {
      lock.unlock()
      return
    }
    cancelled = true
    let started = task
    let alreadyFinished = finished
    let (body, refused) = takeUpload()
    if alreadyFinished { remove() }
    lock.unlock()
    refused?(nil)
    body?.close()
    if !alreadyFinished { started?.cancel() }
  }

  func didReceive(
    response: URLResponse, completion: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    lock.lock()
    let head = headOf(response)
    answered = true
    let waitingPull = pulling
    pulling = nil
    let waiting = opening
    opening = nil
    let body = writer
    lock.unlock()
    waitingPull?(["done": true])
    waiting?(head)
    body?.close()
    completion(.allow)
  }

  func didReceive(data: Data) {
    lock.lock()
    defer { lock.unlock() }
    chunks.append(data)
    bufferedBytes += data.count
    if let waiting = reading {
      reading = nil
      deliver(waiting)
    } else if bufferedBytes > maxBufferedBytes && !suspended, let task {
      suspended = true
      task.suspend()
    }
  }

  func needNewBodyStream(_ completion: @escaping (InputStream?) -> Void) {
    lock.lock()
    if cancelled || finished || answered {
      lock.unlock()
      completion(nil)
      return
    }
    rewind = completion
    rewindTold = false
    let waiting = pulling
    pulling = nil
    if waiting != nil { rewindTold = true }
    lock.unlock()
    waiting?(["rewind": true])
  }

  func didFinishCollecting(_ metrics: URLSessionTaskMetrics) {
    lock.lock()
    networkProtocol = metrics.transactionMetrics.last?.networkProtocolName
    lock.unlock()
  }

  func didComplete(error: Error?) {
    lock.lock()
    let (body, unanswered) = takeUpload()
    finished = true
    if let error {
      let kind = failureKind(of: error)
      failure =
        cancelled || kind == "cancelled"
        ? FlutterError(code: "cancelled", message: "Cancelled", details: nil)
        : FlutterError(code: kind, message: failureDetail(of: error), details: nil)
    }
    answerAll()
    if cancelled { remove() }
    lock.unlock()
    body?.close()
    unanswered?(nil)
  }

  private func newWriter() -> BodyWriter {
    BodyWriter(onSpace: { [weak self] in self?.spaceAvailable() })
  }

  private func answerPull(_ result: @escaping FlutterResult) -> (() -> Void)? {
    if failure != nil || cancelled {
      result(ended)
    } else if answered || finished {
      result(["done": true])
    } else if rewind != nil, !rewindTold {
      rewindTold = true
      result(["rewind": true])
    } else if let accepted = rewind {
      rewindTold = false
      rewind = nil
      pulling = result
      wantsBytes = false
      let replaced = writer
      let body = newWriter()
      writer = body
      return {
        replaced?.close()
        accepted(body.input)
      }
    } else if wantsBytes {
      wantsBytes = false
      result(["want": BodyWriter.bufferSize])
    } else {
      pulling = result
    }
    return nil
  }

  private func takeUpload() -> (BodyWriter?, ((InputStream?) -> Void)?) {
    let taken = (writer, rewind)
    writer = nil
    rewind = nil
    return taken
  }

  private func spaceAvailable() {
    lock.lock()
    let waiting = pulling
    pulling = nil
    if waiting == nil { wantsBytes = true }
    lock.unlock()
    waiting?(["want": BodyWriter.bufferSize])
  }

  private func resumeIfRoom() {
    guard suspended, bufferedBytes <= maxBufferedBytes / 2, let task else { return }
    suspended = false
    task.resume()
  }

  private func headOf(_ response: URLResponse) -> [String: Any] {
    guard let http = response as? HTTPURLResponse else {
      return ["status": 200, "headers": [String: [String]]()]
    }
    var headers: [String: [String]] = [:]
    for (name, value) in http.allHeaderFields {
      headers["\(name)", default: []].append("\(value)")
    }
    return ["status": http.statusCode, "headers": headers]
  }

  private func deliver(_ result: FlutterResult) {
    if chunks.isEmpty, let failure {
      result(failure)
      remove()
      return
    }
    let bytes = drainChunks()
    resumeIfRoom()
    guard finished, failure == nil else {
      result(bytes.map { FlutterStandardTypedData(bytes: $0) })
      return
    }
    var end: [String: Any] = ["end": true]
    if let bytes { end["bytes"] = FlutterStandardTypedData(bytes: bytes) }
    if let networkProtocol { end["protocol"] = networkProtocol }
    result(end)
    remove()
  }

  private func drainChunks() -> Data? {
    defer {
      chunks.removeAll()
      bufferedBytes = 0
    }
    guard chunks.count > 1 else { return chunks.first }
    return chunks.reduce(into: Data(capacity: bufferedBytes)) { $0.append($1) }
  }

  private func answerAll() {
    let waitingPull = pulling
    pulling = nil
    waitingPull?(failure == nil ? ["done": true] : ended)
    if let waitingOpen = opening {
      opening = nil
      waitingOpen(
        failure
          ?? FlutterError(
            code: "protocol", message: "The request ended without a response", details: nil))
      remove()
    }
    if let waiting = reading {
      reading = nil
      deliver(waiting)
    }
  }

  private func remove() {
    guard !removed else { return }
    removed = true
    onFinished(self)
  }
}
