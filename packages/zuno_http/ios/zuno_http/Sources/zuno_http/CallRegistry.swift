import Flutter
import Foundation

protocol NativeCall: AnyObject {
  func cancel()
}

final class CallRegistry<Call: NativeCall> {
  private let lock = NSLock()
  private var calls: [Int: Call] = [:]

  subscript(id: Int) -> Call? {
    lock.lock()
    defer { lock.unlock() }
    return calls[id]
  }

  func find(_ id: Int, _ result: FlutterResult) -> Call? {
    guard let call = self[id] else {
      result(FlutterError(code: "cancelled", message: "No call \(id)", details: nil))
      return nil
    }
    return call
  }

  func replace(_ id: Int, with call: Call) {
    lock.lock()
    let replaced = calls.updateValue(call, forKey: id)
    lock.unlock()
    replaced?.cancel()
  }

  func remove(_ id: Int, _ call: Call) {
    lock.lock()
    if calls[id] === call { calls[id] = nil }
    lock.unlock()
  }

  func cancelAll() {
    lock.lock()
    let all = Array(calls.values)
    calls.removeAll()
    lock.unlock()
    all.forEach { $0.cancel() }
  }
}

extension URLRequest {
  mutating func setHeaders(_ headers: [String: String]) {
    for (name, value) in headers {
      setValue(value, forHTTPHeaderField: name)
    }
    if value(forHTTPHeaderField: "Accept-Language") == nil {
      setValue("*", forHTTPHeaderField: "Accept-Language")
    }
  }
}
