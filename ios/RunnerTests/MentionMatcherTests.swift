import XCTest

@testable import Runner

final class MentionMatcherTests: XCTestCase {
  func testMatchesThePushRuleEvaluatorOnEveryVector() throws {
    let fixture = try NseFixtures.json("nse_mentions_v1.json")
    let notifiers = try XCTUnwrap(fixture["notifiers"]?.array?.compactMap(\.string))
    for vector in try XCTUnwrap(fixture["cases"]?.array) {
      let rules = try XCTUnwrap(vector["rules"]?.string)
      let spec = try XCTUnwrap(NseMentionSpec(fixture["specs"]?[rules]))
      XCTAssertEqual(
        MentionMatcher.isMention(
          content: try XCTUnwrap(vector["content"]),
          sender: try XCTUnwrap(vector["sender"]?.string),
          spec: spec, notifiers: notifiers),
        vector["mention"]?.bool, vector["name"]?.string ?? "")
    }
  }

  func testNamesAreMatchedLiterallyNotAsPatterns() {
    let spec = NseMentionSpec(
      mxid: "@m:x", displayName: "a.b", keywords: [],
      rules: [MentionMatcher.displayName: true])

    XCTAssertFalse(
      MentionMatcher.isMention(
        content: .object(["body": .string("axb here")]), sender: "@s:x", spec: spec,
        notifiers: []))
    XCTAssertTrue(
      MentionMatcher.isMention(
        content: .object(["body": .string("hi a.b")]), sender: "@s:x", spec: spec, notifiers: []))
  }

  func testEveryoneMayNotifyWhenTheRoomAllowsIt() {
    let spec = NseMentionSpec(
      mxid: "@m:x", displayName: nil, keywords: [], rules: [MentionMatcher.roomNotif: true])

    XCTAssertTrue(
      MentionMatcher.isMention(
        content: .object(["body": .string("@room hi")]), sender: "@s:x", spec: spec,
        notifiers: ["*"]))
  }

  func testWithoutABodyOnlyStructuredMentionsCount() {
    let spec = NseMentionSpec(
      mxid: "@m:x", displayName: "M", keywords: [.init(pattern: "*", highlight: true)],
      rules: [MentionMatcher.userMention: true, MentionMatcher.displayName: true])

    XCTAssertFalse(
      MentionMatcher.isMention(content: .object([:]), sender: "@s:x", spec: spec, notifiers: []))
  }
}
