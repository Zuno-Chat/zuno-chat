import Foundation

struct NseNames: Equatable, Sendable {
  let title: String
  let sender: String
  let isDm: Bool
}

struct NseTokens: Equatable, Sendable {
  let t: String
  let e: String
  let o: Int64
}

enum NseComposer {
  static let fixedThread = "zuno"
  static let maxCharacters = 300
  static let maxNameBytes = CallerName.byteLimit
  static let nothingTitle = "Zuno"
  static let newMessage = "New message"
  static let testBody = "Notifications work"

  static func sanitize(_ text: String) -> String {
    let kept = String(
      String.UnicodeScalarView(text.unicodeScalars.filter { $0 == "\n" || !isStripped($0) }))
    guard kept.unicodeScalars.count > maxCharacters else { return kept }
    return String(String.UnicodeScalarView(kept.unicodeScalars.prefix(maxCharacters - 1))) + "…"
  }

  static func name(_ text: String) -> String {
    CallerName.sanitize(text)
  }

  static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
    CallerName.isStripped(scalar)
  }

  static func formattedLocalpart(_ mxid: String) -> String {
    guard mxid.hasPrefix("@"), mxid.utf16.count <= 255, let colon = mxid.firstIndex(of: ":"),
      mxid.index(after: colon) < mxid.endIndex
    else { return "" }
    let localpart = mxid[mxid.index(after: mxid.startIndex)..<colon]
    let words = localpart.replacingOccurrences(of: "_", with: " ")
      .components(separatedBy: " ")
      .map { word in word.isEmpty ? word : word.prefix(1).uppercased() + word.dropFirst() }
    return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func names(room: NseRoomFile?, fetched: NseFetched?, senderId: String?) -> NseNames {
    let sender =
      nonEmpty(fetched?.senderName.map(name))
      ?? nonEmpty(senderId.map(formattedLocalpart).map(name)) ?? ""
    let title =
      nonEmpty(room?.title.map(name)) ?? nonEmpty(fetched?.roomName.map(name))
      ?? (sender.isEmpty ? nothingTitle : sender)
    return NseNames(title: title, sender: sender, isDm: room?.dm ?? fetched?.isDm ?? false)
  }

  static func inviter(event: NseEvent, fetched: NseFetched?) -> String {
    nonEmpty(NseClassifier.inviterName(event).map(name))
      ?? nonEmpty(fetched?.senderName.map(name))
      ?? nonEmpty(name(formattedLocalpart(event.sender))) ?? nothingTitle
  }

  static func messageLines(text: String, names: NseNames) -> (title: String, body: String) {
    let body = names.isDm || names.sender.isEmpty ? text : "\(names.sender): \(text)"
    return (names.title, body)
  }

  static func invitationLines(inviter: String, roomName: String?) -> (title: String, body: String) {
    let room = nonEmpty(roomName.map(name)) ?? ""
    return (inviter, room.isEmpty ? "Invited you to chat" : "Invited you to \(room)")
  }

  static func verificationLines(sender: String) -> (title: String, body: String) {
    (sender, "Wants to verify you")
  }

  static func userInfo(_ tokens: NseTokens, kind: String, floor: Bool = false, rg: String? = nil)
    -> [String: String]
  {
    var info = ["t": tokens.t, "e": tokens.e, "o": String(tokens.o), "k": kind]
    if floor { info["f"] = "1" }
    if let rg { info["rg"] = rg }
    return info
  }

  static func delivery(
    title: String, body: String, thread: String, userInfo: [String: String],
    interruption: NseDelivery.Interruption, sound: NseDelivery.Sound
  ) -> NseDelivery {
    NseDelivery(
      title: sanitize(title), body: sanitize(body), threadId: thread, userInfo: userInfo,
      interruption: interruption, sound: sound, badge: nil, removals: [], usesOriginal: false)
  }

  static func alert(loud: Bool, tone: Bool) -> (NseDelivery.Interruption, NseDelivery.Sound) {
    (loud ? .active : .passive, loud && tone ? .messageTone : .none)
  }

  static func message(
    text: String, keepsTextWhenNameOnly: Bool, names: NseNames, level: PreviewLevel,
    loud: Bool, tone: Bool, tokens: NseTokens
  ) -> NseDelivery {
    if level == .none { return nothing(tokens: tokens, quiet: !loud, tone: tone) }
    let shown = level == .name && !keepsTextWhenNameOnly ? newMessage : text
    let lines = messageLines(text: shown, names: names)
    let (interruption, sound) = alert(loud: loud, tone: tone)
    return delivery(
      title: lines.title, body: lines.body, thread: tokens.t,
      userInfo: userInfo(tokens, kind: "msg"), interruption: interruption, sound: sound)
  }

  static func floor(
    names: NseNames, level: PreviewLevel, loud: Bool, tone: Bool, tokens: NseTokens
  ) -> NseDelivery {
    let lines = messageLines(text: newMessage, names: names)
    let (interruption, sound) = alert(loud: loud, tone: tone)
    return delivery(
      title: lines.title, body: lines.body, thread: threadId(level, tokens),
      userInfo: userInfo(tokens, kind: "msg", floor: true), interruption: interruption,
      sound: sound)
  }

  static func nothing(tokens: NseTokens, quiet: Bool, tone: Bool) -> NseDelivery {
    let (interruption, sound) = alert(loud: !quiet, tone: tone)
    return delivery(
      title: nothingTitle, body: newMessage, thread: fixedThread,
      userInfo: userInfo(tokens, kind: "msg", floor: true), interruption: interruption,
      sound: sound)
  }

  static func invitation(inviter: String, roomName: String?, tone: Bool, tokens: NseTokens)
    -> NseDelivery
  {
    let lines = invitationLines(inviter: inviter, roomName: roomName)
    let (interruption, sound) = alert(loud: true, tone: tone)
    return delivery(
      title: lines.title, body: lines.body, thread: tokens.t,
      userInfo: userInfo(tokens, kind: "inv"), interruption: interruption, sound: sound)
  }

  static func verification(sender: String, tone: Bool, tokens: NseTokens) -> NseDelivery {
    let lines = verificationLines(sender: sender)
    let (interruption, sound) = alert(loud: true, tone: tone)
    return delivery(
      title: lines.title, body: lines.body, thread: tokens.t,
      userInfo: userInfo(tokens, kind: "sys"), interruption: interruption, sound: sound)
  }

  static func callLine(names: NseNames, video: Bool, tokens: NseTokens) -> NseDelivery {
    delivery(
      title: names.title, body: video ? "Video call" : "Voice call", thread: tokens.t,
      userInfo: userInfo(tokens, kind: "call"), interruption: .passive, sound: .none)
  }

  static func fallbackRing(
    names: NseNames, video: Bool, ringtone: Bool, tokens: NseTokens, rg: String
  ) -> NseDelivery {
    delivery(
      title: names.title, body: video ? "Incoming video call" : "Incoming voice call",
      thread: tokens.t, userInfo: userInfo(tokens, kind: "call", rg: rg),
      interruption: .timeSensitive, sound: ringtone ? .ring : .silentRing)
  }

  static func readNotice(names: NseNames, tokens: NseTokens) -> NseDelivery {
    delivery(
      title: names.title, body: newMessage, thread: tokens.t,
      userInfo: userInfo(tokens, kind: "sys"), interruption: .passive, sound: .none)
  }

  static func activity(names: NseNames, level: PreviewLevel, video: Bool?, tokens: NseTokens)
    -> NseDelivery
  {
    let body = video.map { $0 ? "Video call" : "Voice call" } ?? "New activity"
    return delivery(
      title: names.title, body: body, thread: threadId(level, tokens),
      userInfo: userInfo(tokens, kind: "sys"), interruption: .passive, sound: .none)
  }

  static func repost(_ delivered: NseDelivered, tokens: NseTokens) -> NseDelivery {
    guard delivered.pushed else {
      return delivery(
        title: delivered.title, body: delivered.body, thread: tokens.t,
        userInfo: userInfo(tokens, kind: "msg"), interruption: .passive, sound: .none)
    }
    return NseDelivery(
      title: delivered.title, body: delivered.body, threadId: delivered.threadId,
      userInfo: delivered.userInfo, interruption: .passive, sound: .none, badge: nil,
      removals: [delivered.identifier], usesOriginal: false)
  }

  static func test() -> NseDelivery {
    NseDelivery(
      title: nothingTitle, body: testBody, threadId: fixedThread,
      userInfo: ["k": "sys", "test": "1"],
      interruption: .active, sound: .original, badge: nil, removals: [], usesOriginal: false)
  }

  static func badge(
    unread: [String]?, delivered: [NseDelivered], removed: Set<String>,
    current: (t: String, counts: Bool)?
  ) -> Int? {
    guard let unread else { return nil }
    var rooms = Set(unread)
    for note in delivered where !removed.contains(note.identifier) {
      if let t = note.t, note.k == "msg" || note.k == "inv" { rooms.insert(t) }
    }
    if let current, current.counts { rooms.insert(current.t) }
    return rooms.count
  }

  private static func threadId(_ level: PreviewLevel, _ tokens: NseTokens) -> String {
    level == .none ? fixedThread : tokens.t
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return text
  }
}
