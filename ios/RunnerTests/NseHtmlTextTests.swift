import Foundation
import XCTest

@testable import Runner

final class NseHtmlTextTests: XCTestCase {
  func testMatchesTheSdkPlainTextOnEveryVector() throws {
    for vector in try NseFixtures.cases("nse_html_v1.json") {
      let html = try XCTUnwrap(vector["html"]?.string)
      XCTAssertEqual(NseHtmlText.plainText(html), vector["text"]?.string, html)
    }
  }

  func testUnknownEntitiesAndStrayBracketsStayAsText() {
    XCTAssertEqual(NseHtmlText.plainText("a &bogus; b"), "a &bogus; b")
    XCTAssertEqual(NseHtmlText.plainText("1 < 2 and 3 > 2"), "1 < 2 and 3 > 2")
    XCTAssertEqual(NseHtmlText.plainText("ends with <"), "ends with <")
  }

  func testAReplyIsDroppedEvenWhenItsTagsAreUppercase() {
    XCTAssertEqual(NseHtmlText.plainText("<MX-REPLY>quoted</MX-REPLY>answer"), "answer")
  }

  func testAReplyWithAVeryLongQuoteStillGivesTheAnswer() {
    let html =
      "<mx-reply><blockquote>" + String(repeating: "q", count: 20_000)
      + "</blockquote></mx-reply>answer"

    XCTAssertEqual(NseHtmlText.plainText(html), "answer")
  }

  func testAListStartingAtTheLargestIntegerWrapsLikeTheSdk() {
    XCTAssertEqual(
      NseHtmlText.plainText("<ol start=\"9223372036854775807\"><li>a</li><li>b</li></ol>"),
      "9223372036854775807. a\n-9223372036854775808. b")
  }

  func testDeeplyNestedTagsStillReturnTheirText() {
    let text = plainTextOnASmallStack(String(repeating: "<b>", count: 2_000) + "x")

    XCTAssertTrue(text.contains("x"))
  }

  func testNestedQuotesWithManyLineBreaksStayCheap() {
    let text = plainTextOnASmallStack(
      String(repeating: "<blockquote>", count: 800) + String(repeating: "x<br>", count: 1_600))

    XCTAssertTrue(text.contains("x"))
  }

  func testNestedListsWithALineBreakStayCheap() {
    let text = plainTextOnASmallStack(String(repeating: "<ul><li>", count: 800) + "x<br>y")

    XCTAssertFalse(text.isEmpty)
  }

  private final class Box: @unchecked Sendable {
    var text = ""
  }

  private func plainTextOnASmallStack(_ html: String) -> String {
    let box = Box()
    let finished = DispatchSemaphore(value: 0)
    let thread = Thread {
      box.text = NseHtmlText.plainText(html)
      finished.signal()
    }
    thread.stackSize = 512 * 1024
    thread.start()
    guard finished.wait(timeout: .now() + 5) == .success else {
      XCTFail("plainText did not return within 5 seconds")
      return ""
    }
    return box.text
  }
}
