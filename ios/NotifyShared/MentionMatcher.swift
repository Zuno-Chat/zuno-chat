import Foundation

enum MentionMatcher {
  static let suppressNotices = ".m.rule.suppress_notices"
  static let userMention = ".m.rule.is_user_mention"
  static let displayName = ".m.rule.contains_display_name"
  static let roomMention = ".m.rule.is_room_mention"
  static let roomNotif = ".m.rule.roomnotif"

  static func isMention(
    content: NseJson, sender: String, spec: NseMentionSpec, notifiers: [String]
  ) -> Bool {
    let rules = spec.rules
    if rules[suppressNotices] == true, content["msgtype"]?.string == "m.notice" { return false }
    let body = content["body"]?.string
    let mentions = content["m.mentions"]
    let mayNotifyRoom = notifiers.contains("*") || notifiers.contains(sender)
    if rules[userMention] == true,
      mentions?["user_ids"]?.array?.contains(.string(spec.mxid)) == true
    {
      return true
    }
    if rules[displayName] == true, let name = spec.displayName, !name.isEmpty, let body,
      matches(body, core: NSRegularExpression.escapedPattern(for: name))
    {
      return true
    }
    if rules[roomMention] == true, mentions?["room"] == .bool(true), mayNotifyRoom { return true }
    if rules[roomNotif] == true, mayNotifyRoom, let body, matches(body, core: glob("@room")) {
      return true
    }
    guard let body else { return false }
    for keyword in spec.keywords where matches(body, core: glob(keyword.pattern)) {
      return keyword.highlight
    }
    return false
  }

  static func glob(_ pattern: String) -> String {
    NSRegularExpression.escapedPattern(for: pattern)
      .replacingOccurrences(of: "\\*", with: ".*")
      .replacingOccurrences(of: "\\?", with: ".")
  }

  private static func matches(_ body: String, core: String) -> Bool {
    guard
      let regex = try? NSRegularExpression(
        pattern: "(^|[^A-Za-z0-9_])\(core)($|[^A-Za-z0-9_])", options: [.caseInsensitive])
    else { return false }
    return regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
  }
}
