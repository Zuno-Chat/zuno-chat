import Flutter
import XCTest

@testable import zuno_http

private final class FakeTask: SessionTask {
  var resumes = 0
  var suspends = 0
  var cancels = 0

  func resume() { resumes += 1 }
  func suspend() { suspends += 1 }
  func cancel() { cancels += 1 }
}

private final class Reply {
  private(set) var answers: [Any?] = []

  var result: FlutterResult { { self.answers.append($0) } }

  var single: Any? {
    XCTAssertEqual(answers.count, 1)
    return answers.first ?? nil
  }
}

private final class Counted: NativeCall {
  var cancels = 0

  func cancel() { cancels += 1 }
}

private let url = URL(string: "https://example.org/a")!

private func code(_ answer: Any?) -> String? { (answer as? FlutterError)?.code }

private final class Harness {
  let task = FakeTask()
  let opening = Reply()
  private(set) var removals = 0
  private(set) var call: SessionCall!

  init(hasBody: Bool = false) {
    call = SessionCall(
      hasBody: hasBody, startTask: { [task] _, _ in task },
      onFinished: { [unowned self] _ in self.removals += 1 })
    call.open(URLRequest(url: url), result: opening.result)
  }

  @discardableResult
  func head(status: Int = 200) -> URLSession.ResponseDisposition? {
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "text/plain"])!
    var disposition: URLSession.ResponseDisposition?
    call.didReceive(response: response) { disposition = $0 }
    return disposition
  }

  func read() -> Any? {
    let reply = Reply()
    call.read(reply.result)
    return reply.single
  }

  func pull() -> Any? {
    let reply = Reply()
    call.pullBody(reply.result)
    return reply.single
  }
}

final class SessionCallTests: XCTestCase {
  func testOpenStartsTheTask() {
    let h = Harness()

    XCTAssertEqual(h.task.resumes, 1)
  }

  func testTheHeadAnswersOpenAndLetsTheBodyIn() {
    let h = Harness()

    let disposition = h.head(status: 201)

    let head = h.opening.single as? [String: Any]
    XCTAssertEqual(head?["status"] as? Int, 201)
    XCTAssertEqual((head?["headers"] as? [String: [String]])?["Content-Type"], ["text/plain"])
    XCTAssertEqual(disposition, .allow)
  }

  func testOnceTheHeadArrivesTheUploadIsDone() {
    let h = Harness(hasBody: true)

    h.head()

    XCTAssertEqual(h.pull() as? [String: Bool], ["done": true])
  }

  func testAFinishedRequestReadsAsItsBytesWithTheEndThenLeaves() {
    let h = Harness()
    h.head()
    h.call.didReceive(data: Data([1, 2]))

    h.call.didComplete(error: nil)
    XCTAssertEqual(h.removals, 0)
    let end = h.read() as? [String: Any]

    XCTAssertEqual(end?["end"] as? Bool, true)
    XCTAssertEqual((end?["bytes"] as? FlutterStandardTypedData)?.data, Data([1, 2]))
    XCTAssertEqual(h.removals, 1)
  }

  func testAFailureBeforeTheHeadAnswersOpenWithItsKindAndLeaves() {
    let h = Harness()

    h.call.didComplete(error: URLError(.cannotFindHost))

    XCTAssertEqual(code(h.opening.single), "dns")
    XCTAssertEqual(h.removals, 1)
  }

  func testAFailureAfterSomeDataDeliversTheBytesThenTheErrorThenLeaves() {
    let h = Harness()
    h.head()
    h.call.didReceive(data: Data([1, 2]))

    h.call.didComplete(error: URLError(.networkConnectionLost))

    XCTAssertEqual((h.read() as? FlutterStandardTypedData)?.data, Data([1, 2]))
    XCTAssertEqual(h.removals, 0)
    XCTAssertEqual(code(h.read()), "connectionLost")
    XCTAssertEqual(h.removals, 1)
  }

  func testACancelDuringAPendingRewindRefusesItOnceAndEndsAsCancelled() {
    let h = Harness(hasBody: true)
    var streams: [InputStream?] = []
    h.call.needNewBodyStream { streams.append($0) }

    h.call.cancel()
    h.call.didComplete(error: URLError(.cancelled))

    XCTAssertEqual(streams.count, 1)
    XCTAssertNil(streams.first ?? nil)
    XCTAssertEqual(h.task.cancels, 1)
    XCTAssertEqual(code(h.opening.single), "cancelled")
    XCTAssertEqual(h.removals, 1)
  }

  func testACancelAfterTheRequestFinishedLeavesWithoutCancellingTheTask() {
    let h = Harness()
    h.head()
    h.call.didComplete(error: nil)

    h.call.cancel()

    XCTAssertEqual(h.removals, 1)
    XCTAssertEqual(h.task.cancels, 0)
  }

  func testAFullBufferSuspendsTheTaskUntilDartReads() {
    let h = Harness()
    h.head()

    h.call.didReceive(data: Data(count: 300_000))
    XCTAssertEqual(h.task.suspends, 1)
    _ = h.read()

    XCTAssertEqual(h.task.resumes, 2)
  }

  func testAnOldCallEndingLeavesTheNewCallWithItsIdInPlace() {
    let registry = CallRegistry<Counted>()
    let old = Counted()
    let new = Counted()
    registry.replace(1, with: old)

    registry.replace(1, with: new)
    registry.remove(1, old)

    XCTAssertEqual(old.cancels, 1)
    XCTAssertTrue(registry[1] === new)
  }
}
