import Foundation

protocol SessionTaskHandler: AnyObject {
  func didReceive(
    response: URLResponse, completion: @escaping (URLSession.ResponseDisposition) -> Void)
  func didReceive(data: Data)
  func needNewBodyStream(_ completion: @escaping (InputStream?) -> Void)
  func didFinishCollecting(_ metrics: URLSessionTaskMetrics)
  func didComplete(error: Error?)
  func didOpen()
}

extension SessionTaskHandler {
  func didReceive(
    response: URLResponse, completion: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    completion(.allow)
  }
  func didReceive(data: Data) {}
  func needNewBodyStream(_ completion: @escaping (InputStream?) -> Void) { completion(nil) }
  func didFinishCollecting(_ metrics: URLSessionTaskMetrics) {}
  func didOpen() {}
}

protocol SessionTask: AnyObject {
  func resume()
  func suspend()
  func cancel()
}

extension URLSessionTask: SessionTask {}

let unboundedRequestTimeout: TimeInterval = 24 * 60 * 60

final class SharedSession: NSObject, URLSessionDataDelegate, URLSessionWebSocketDelegate {
  static let shared = SharedSession()

  private let lock = NSLock()
  private var handlers: [Int: SessionTaskHandler] = [:]
  private(set) var session: URLSession!

  override init() {
    super.init()
    let queue = OperationQueue()
    queue.name = "zuno.http.session"
    queue.maxConcurrentOperationCount = 1
    session = URLSession(configuration: Self.configuration(), delegate: self, delegateQueue: queue)
  }

  static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCredentialStorage = nil
    configuration.httpMaximumConnectionsPerHost = 16
    configuration.timeoutIntervalForRequest = unboundedRequestTimeout
    if #available(iOS 26.6, *) {
      configuration.usesClassicLoadingMode = false
      configuration.enablesEarlyData = false
    }
    return configuration
  }

  func register(_ task: URLSessionTask, handler: SessionTaskHandler) {
    lock.lock()
    handlers[task.taskIdentifier] = handler
    lock.unlock()
  }

  func dataTask(with request: URLRequest, handler: SessionTaskHandler) -> SessionTask {
    let task = session.dataTask(with: request)
    register(task, handler: handler)
    return task
  }

  private func handler(for task: URLSessionTask) -> SessionTaskHandler? {
    lock.lock()
    defer { lock.unlock() }
    return handlers[task.taskIdentifier]
  }

  private func forget(_ task: URLSessionTask) {
    lock.lock()
    handlers[task.taskIdentifier] = nil
    lock.unlock()
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let handler = handler(for: dataTask) else {
      completionHandler(.cancel)
      return
    }
    handler.didReceive(response: response, completion: completionHandler)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    handler(for: dataTask)?.didReceive(data: data)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
  ) {
    guard let handler = handler(for: task) else {
      completionHandler(nil)
      return
    }
    handler.needNewBodyStream(completionHandler)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    handler(for: task)?.didFinishCollecting(metrics)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let found = handler(for: task)
    forget(task)
    found?.didComplete(error: error)
  }

  func urlSession(
    _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    handler(for: webSocketTask)?.didOpen()
  }
}
