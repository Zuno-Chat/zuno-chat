enum ReplyNotSentNotice {
  static let identifierPrefix = "zuno.reply_not_sent."

  static func isNotice(_ identifier: String) -> Bool {
    identifier.hasPrefix(identifierPrefix)
  }
}
