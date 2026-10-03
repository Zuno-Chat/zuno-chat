import Foundation

extension NsePipeline {
  func catchUp(_ context: NseContext, safeMode: Bool) async -> CatchUpOutcome? {
    guard let data = context.catchUpBody,
      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      body["missed"] != nil || body["read_rooms"] != nil
    else { return nil }
    let elapsed = Double(env.clock.nowMs() - context.start) / 1000
    let platform = env.catchUpPlatform(
      NseCatchUpPlatform.Sources(
        roomToken: { context.hashing.t($0) },
        eventToken: { context.hashing.e($0) },
        alreadyShown: { context.store.isShown($0) },
        recordShown: { context.store.recordShown($0, in: NotifyFile.shownNse) },
        render: { item, decrypt in
          self.renderCatchUp(item, decrypt: decrypt && !safeMode, context: context)
        }))
    let outcome = await CatchUp.run(
      body: body, level: context.meta.level.rawValue, pushedEventId: context.eventId,
      deadline: Date().addingTimeInterval(CatchUp.budget - elapsed), platform: platform)
    if [body["missed"], body["read_rooms"]].contains(where: { ($0 as? [Any])?.isEmpty == false }) {
      env.signals.log(
        "nse_catchup",
        [
          ("posted", String(outcome.posted)), ("hidden", String(outcome.hidden)),
          ("read", String(outcome.readRoomTokens.count)),
          ("overflow", String(outcome.overflow)), ("floor", String(outcome.floors)),
        ])
    }
    return outcome
  }

  func renderCatchUp(_ item: MissedEvent, decrypt: Bool, context: NseContext) -> CatchUpRender {
    guard var event = NseEvent(NseJson(item.item)["event"]), event.roomId == item.roomId,
      event.eventId == item.eventId
    else { return .hidden }
    let fetched = NseFetched(
      event: event, senderName: item.senderName, roomName: item.roomName, isDm: item.isDm,
      highlight: item.highlight, serverTs: nil)
    let t = context.hashing.t(item.roomId)
    let itemContext = NseContext(
      push: NsePush(
        id: item.eventId, roomId: item.roomId, eventId: item.eventId,
        receivedMs: context.push.receivedMs),
      roomId: item.roomId, eventId: item.eventId, keys: context.keys, store: context.store,
      hashing: context.hashing, meta: context.meta, t: t, e: context.hashing.e(item.eventId),
      start: context.start,
      room: context.meta.level == .none ? nil : context.store.room(token: t, roomId: item.roomId))
    let tokens = itemContext.tokens(o: event.originServerTs / 1000)
    if event.type == "m.room.encrypted" {
      var plain: NseEvent?
      if decrypt {
        switch decryptNow(event, itemContext) {
        case .event(let decrypted): plain = decrypted
        case .duplicate: return .hidden
        case .floor: plain = nil
        }
      }
      guard let plain else {
        let names = NseComposer.names(
          room: itemContext.room, fetched: fetched, senderId: event.sender)
        let line = NseComposer.floor(
          names: names, level: context.meta.level, loud: false, tone: false, tokens: tokens)
        return .shown(title: line.title, body: line.body, kind: "msg", floor: true)
      }
      event = plain
    }
    let names = NseComposer.names(room: itemContext.room, fetched: fetched, senderId: event.sender)
    let now = env.clock.nowMs()
    if let summary = NseClassifier.callSummary(event), event.sender != context.meta.user,
      summary.status == "missed" || summary.status == "declined"
    {
      context.store.appendMark(
        NseMark(
          kind: "summary", room: item.roomId, call: summary.callId, status: summary.status,
          ts: now))
      env.signals.post(.callsChanged)
      if summary.status == "missed" {
        let uuid = CallIdentity.uuid(roomId: item.roomId, callId: summary.callId).uuidString
        if context.store.state().missed.contains(uuid) { return .hidden }
        context.store.updateState {
          $0.missed = SeenSets.appending(uuid, to: $0.missed, limit: SeenSets.missedLimit)
        }
      }
    }
    switch NseClassifier.classify(event, ownUserId: context.meta.user, nowMs: now) {
    case .hidden, .ring:
      return .hidden
    case .invitation(let roomName):
      let key = context.hashing.e("invite:\(item.roomId)")
      if context.store.isShown(key) { return .hidden }
      context.store.recordShown([key], in: NotifyFile.shownNse)
      context.store.appendMark(NseMark(kind: "invite", room: item.roomId, ts: now))
      let line = NseComposer.invitation(
        inviter: NseComposer.inviter(event: event, fetched: fetched), roomName: roomName,
        tone: false, tokens: tokens)
      return .shown(title: line.title, body: line.body, kind: "inv")
    case .verification:
      let line = NseComposer.verification(
        sender: names.sender.isEmpty ? names.title : names.sender, tone: false, tokens: tokens)
      return .shown(title: line.title, body: line.body, kind: "sys")
    case .message(let text, let keepsText):
      let line = NseComposer.message(
        text: text, keepsTextWhenNameOnly: keepsText, names: names, level: context.meta.level,
        loud: false, tone: false, tokens: tokens)
      return .shown(title: line.title, body: line.body, kind: "msg")
    }
  }
}
