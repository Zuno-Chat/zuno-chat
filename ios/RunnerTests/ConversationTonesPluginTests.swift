import XCTest

@testable import Runner

final class ConversationTonesPluginTests: XCTestCase {
  func testNamesTheFileForEachTone() {
    XCTAssertEqual(ConversationTonesPlugin.soundName(for: "incoming"), "conversation_in")
    XCTAssertEqual(ConversationTonesPlugin.soundName(for: "sent"), "conversation_out")
    XCTAssertNil(ConversationTonesPlugin.soundName(for: "other"))
  }
}
