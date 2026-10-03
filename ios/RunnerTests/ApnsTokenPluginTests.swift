@preconcurrency import Flutter
import XCTest

@testable import Runner

@MainActor
final class ApnsTokenPluginTests: XCTestCase {
  func testTheEnvironmentMethodAnswersThePushEnvironmentOfThisBuild() async {
    let reply = await channelReply(from: ApnsTokenPlugin(), method: "environment")

    XCTAssertEqual(reply.answer as? String, PushEnvironment.current.rawValue)
  }

  func testAnUnknownMethodIsNotImplemented() async {
    for method in ["unknown", "Environment", ""] {
      let reply = await channelReply(from: ApnsTokenPlugin(), method: method)

      XCTAssertIdentical(reply.answer as? NSObject, FlutterMethodNotImplemented, method)
    }
  }
}
