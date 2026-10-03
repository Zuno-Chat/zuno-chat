enum ReplyNotSentNotice {
  static let body = "Message not sent. Open Zuno and send it again."
  static let identifierPrefix = "zuno.reply_not_sent."

  static func isNotice(_ identifier: String) -> Bool {
    identifier.hasPrefix(identifierPrefix)
  }
}
