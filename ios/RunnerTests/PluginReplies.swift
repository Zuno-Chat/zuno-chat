@preconcurrency import Flutter
import XCTest

let systemTimeout: TimeInterval = 60

@MainActor
extension XCTestCase {
  func channelReply(
    from plugin: any FlutterPlugin, method: String, arguments: Any? = nil
  ) async -> (answer: Any?, onMainThread: Bool) {
    var reply: (answer: Any?, onMainThread: Bool) = (nil, false)
    let answered = expectation(description: "\(method) reply")
    plugin.handle?(FlutterMethodCall(methodName: method, arguments: arguments)) { answer in
      reply = (answer, Thread.isMainThread)
      answered.fulfill()
    }
    await fulfillment(of: [answered], timeout: systemTimeout)
    return reply
  }

  func runWithinSystemTimeout(_ body: @escaping @MainActor () async -> Void) async {
    let finished = expectation(description: "body finishes")
    Task {
      await body()
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: systemTimeout)
  }
}
