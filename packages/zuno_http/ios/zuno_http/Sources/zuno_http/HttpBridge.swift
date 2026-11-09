import Flutter
import Foundation

final class HttpBridge {
  private let calls = CallRegistry<SessionCall>()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let id = arguments["id"] as? Int ?? 0
    switch call.method {
    case "ready":
      result(nil)
    case "open":
      open(id: id, arguments: arguments, result: result)
    case "pullBody":
      calls.find(id, result)?.pullBody(result)
    case "write":
      let chunk = (arguments["chunk"] as? FlutterStandardTypedData)?.data ?? Data()
      calls.find(id, result)?.write(chunk, last: arguments["last"] as? Bool ?? false, result: result)
    case "read":
      calls.find(id, result)?.read(result)
    case "status":
      result("unknown")
    case "cancel":
      calls[id]?.cancel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func cancelAll() {
    calls.cancelAll()
  }

  private func open(id: Int, arguments: [String: Any], result: @escaping FlutterResult) {
    guard let text = arguments["url"] as? String, let url = URL(string: text) else {
      result(FlutterError(code: "protocol", message: "Invalid URL", details: nil))
      return
    }
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: unboundedRequestTimeout)
    request.httpMethod = arguments["method"] as? String ?? "GET"
    request.setHeaders(arguments["headers"] as? [String: String] ?? [:])
    if let length = arguments["bodyLength"] as? Int {
      request.setValue(String(length), forHTTPHeaderField: "Content-Length")
    }
    let sessionCall = SessionCall(
      hasBody: arguments["hasBody"] as? Bool ?? false,
      onFinished: { [weak calls] finished in calls?.remove(id, finished) })
    calls.replace(id, with: sessionCall)
    sessionCall.open(request, result: result)
  }
}
