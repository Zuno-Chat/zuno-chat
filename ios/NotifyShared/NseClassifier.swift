import Foundation

enum NseClass: Equatable, Sendable {
  case message(text: String, keepsTextWhenNameOnly: Bool)
  case ring(callId: String, video: Bool)
  case invitation(roomName: String?)
  case verification
  case hidden
}

struct NseCallSummary: Equatable, Sendable {
  let callId: String
  let kind: String
  let status: String
  let durationMs: Int64

  var label: String { kind == "video" ? "Video call" : "Voice call" }

  var displayBody: String {
    switch status {
    case "missed": return "Missed \(label)"
    case "declined": return "\(label) declined"
    default:
      let seconds = durationMs / 1000
      let minutes = seconds / 60
      let rest = seconds % 60
      return "\(label) · \(minutes):\(rest < 10 ? "0" : "")\(rest)"
    }
  }
}

enum NseClassifier {
  static let maxInviteAgeMs: Int64 = 45_000
  static let callInviteType = "im.zuno.call_invite"
  static let callDeclineType = "im.zuno.call_decline"
  static let callSummaryType = "im.zuno.call_summary"
  static let verificationRequestType = "m.key.verification.request"

  static func classify(_ event: NseEvent, ownUserId: String, nowMs: Int64) -> NseClass {
    let msgtype = messageType(event)
    if msgtype == callSummaryType, callSummary(event)?.status != "missed" { return .hidden }
    if let ring = ring(event, ownUserId: ownUserId, nowMs: nowMs) { return ring }
    if let invitation = invitation(event, ownUserId: ownUserId) { return invitation }
    if isVerificationRequest(event, ownUserId: ownUserId) { return .verification }
    return message(event, ownUserId: ownUserId)
  }

  static func callSummary(_ event: NseEvent) -> NseCallSummary? {
    guard messageType(event) == callSummaryType,
      let callId = event.content["call_id"]?.string,
      let kind = event.content["kind"]?.string,
      let status = event.content["status"]?.string,
      ["missed", "declined", "ended"].contains(status)
    else { return nil }
    return NseCallSummary(
      callId: callId, kind: kind, status: status,
      durationMs: event.content["duration_ms"]?.int64 ?? 0)
  }

  static func messageType(_ event: NseEvent) -> String {
    event.type == "m.sticker" ? "m.sticker" : (event.content["msgtype"]?.string ?? "m.text")
  }

  static func relationType(_ event: NseEvent) -> String? {
    event.content["m.relates_to"]?["rel_type"]?.string
  }

  static func inviteRoomName(_ event: NseEvent) -> String? {
    let state = event.inviteRoomState.first { $0["type"]?.string == "m.room.name" }
    guard let name = state?["content"]?["name"]?.string, !name.isEmpty else { return nil }
    return name
  }

  static func inviterName(_ event: NseEvent) -> String? {
    let member = event.inviteRoomState.first {
      $0["type"]?.string == "m.room.member" && $0["state_key"]?.string == event.sender
    }
    guard let name = member?["content"]?["displayname"]?.string, !name.isEmpty else { return nil }
    return name
  }

  static func summaryText(_ event: NseEvent) -> (text: String, isCallSummary: Bool) {
    if event.redacted { return ("Message deleted", false) }
    guard event.type == "m.room.message" || event.type == "m.sticker" else {
      return ("\(event.type) event", false)
    }
    let msgtype = messageType(event)
    if isCallSignaling(msgtype) || isVerificationSignaling(msgtype) { return (body(event), false) }
    if let summary = callSummary(event) { return (summary.displayBody, true) }
    if msgtype == "m.image" || msgtype == "m.sticker" { return (caption(event) ?? "Photo", false) }
    if msgtype == "m.video" { return (caption(event) ?? "Video", false) }
    if msgtype == "m.audio", event.content["org.matrix.msc3245.voice"] != nil {
      return ("Voice message", false)
    }
    if ["m.image", "m.sticker", "m.video", "m.audio", "m.file"].contains(msgtype) {
      return (body(event), false)
    }
    if msgtype == "m.location" { return ("Location", false) }
    return (stripReplyFallback(plaintextBody(event)), false)
  }

  static func body(_ event: NseEvent) -> String {
    if event.redacted { return "Redacted" }
    let text = event.content["body"]?.string ?? ""
    return text.isEmpty ? "Unknown message format of type \"\(event.type)\"" : text
  }

  static func plaintextBody(_ event: NseEvent) -> String {
    let formatted = event.content["formatted_body"]?.string ?? ""
    guard !formatted.isEmpty, event.content["format"]?.string == "org.matrix.custom.html" else {
      return body(event)
    }
    return NseHtmlText.plainText(formatted)
  }

  static func stripReplyFallback(_ body: String) -> String {
    guard body.hasPrefix("> <") else { return body }
    var result = ""
    var inPrefix = true
    for line in body.components(separatedBy: "\n") {
      if inPrefix && (line.isEmpty || line.hasPrefix("> ")) { continue }
      inPrefix = false
      result += result.isEmpty ? line : "\n\(line)"
    }
    return result
  }

  private static func caption(_ event: NseEvent) -> String? {
    let text = body(event)
    guard let filename = event.content["filename"]?.string, !text.isEmpty, text != filename
    else { return nil }
    return text
  }

  private static func isCallSignaling(_ msgtype: String) -> Bool {
    msgtype == callInviteType || msgtype == callDeclineType
  }

  private static func isVerificationSignaling(_ msgtype: String) -> Bool {
    msgtype.hasPrefix("m.key.verification.")
  }

  private static func isDisplayable(_ event: NseEvent) -> Bool {
    if relationType(event) == "m.replace" { return false }
    let isRealMessage =
      event.type == "m.room.message" || event.type == "m.sticker"
      || event.type == "m.room.encrypted"
    guard isRealMessage else { return false }
    let msgtype = messageType(event)
    if isVerificationSignaling(msgtype) { return false }
    return !isCallSignaling(msgtype)
  }

  private static func ring(_ event: NseEvent, ownUserId: String, nowMs: Int64) -> NseClass? {
    guard event.sender != ownUserId, messageType(event) == callInviteType,
      nowMs - event.originServerTs <= maxInviteAgeMs,
      let callId = event.content["call_id"]?.string,
      let kind = event.content["kind"]?.string
    else { return nil }
    return .ring(callId: callId, video: kind == "video")
  }

  private static func invitation(_ event: NseEvent, ownUserId: String) -> NseClass? {
    guard event.type == "m.room.member", event.stateKey == ownUserId,
      event.content["membership"]?.string == "invite", event.sender != ownUserId
    else { return nil }
    return .invitation(roomName: inviteRoomName(event))
  }

  private static func isVerificationRequest(_ event: NseEvent, ownUserId: String) -> Bool {
    event.type == "m.room.message" && messageType(event) == verificationRequestType
      && event.sender != ownUserId && event.content["to"]?.string == ownUserId
  }

  private static func message(_ event: NseEvent, ownUserId: String) -> NseClass {
    guard event.sender != ownUserId, isDisplayable(event), event.type == "m.room.message"
    else { return .hidden }
    let summary = summaryText(event)
    return .message(text: summary.text, keepsTextWhenNameOnly: summary.isCallSummary)
  }
}
