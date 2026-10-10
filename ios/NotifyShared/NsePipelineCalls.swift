import Foundation

extension NsePipeline {
  static let ledgerWaitMs: Int64 = 8000
  static let ledgerPollMs: Int64 = 250
  static let statusBudgetMs: Int64 = 23_000
  static let fallbackAfterSentMs: Int64 = 8000

  func ring(
    callId: String, video: Bool, names: NseNames, context: NseContext, credential: String,
    baseUrl: String, tokens: NseTokens, best: @Sendable (NseDelivery) -> Void
  ) async -> NseResult {
    let uuid = CallIdentity.uuid(roomId: context.roomId, callId: callId)
    let quiet = NseResult(
      delivery: NseComposer.callLine(names: names, video: video, tokens: tokens),
      outcome: .callHandled)
    if ledgerHas(uuid, context) { return quiet }
    best(quiet.delivery)
    let budgetEnd = context.start + Self.statusBudgetMs
    if await waitForLedger(
      uuid, context, until: min(env.clock.nowMs() + Self.ledgerWaitMs, budgetEnd))
    {
      return quiet
    }
    let fallback = NseResult(
      delivery: NseComposer.fallbackRing(
        names: names, video: video, ringtone: context.meta.ringtone, tokens: tokens,
        rg: context.hashing.rg(uuid)),
      outcome: .fallbackRing)
    best(fallback.delivery)
    let budget = budgetEnd - env.clock.nowMs()
    guard budget > 0 else { return fallback }
    let reply = await RingStatusClient(transport: env.transport).status(
      baseUrl: baseUrl, credential: credential, roomId: context.roomId, callId: callId,
      waitMs: Int(budget))
    if ledgerHas(uuid, context) { return quiet }
    switch reply.status {
    case .suppressed(let rule):
      return rule == RingStatusClient.voipFailingRule ? fallback : quiet
    case .pending:
      return quiet
    case .failed, .noToken, .unknown:
      return fallback
    case .sent(let sentTs):
      let serverNow = reply.serverTs ?? env.clock.nowMs()
      let sent = sentTs ?? serverNow
      let due = env.clock.nowMs() + max(0, sent + Self.fallbackAfterSentMs - serverNow)
      return await waitForLedger(uuid, context, until: min(due, budgetEnd)) ? quiet : fallback
    }
  }

  func invitation(
    event: NseEvent, fetched: NseFetched, roomName: String?, context: NseContext
  ) async -> NseResult {
    let key = context.hashing.e("invite:\(context.roomId)")
    if context.store.isShown(key) { return await duplicate(context) }
    context.store.recordShown([key], in: NotifyFile.shownNse)
    context.store.appendMark(NseMark(kind: "invite", room: context.roomId, ts: env.clock.nowMs()))
    return NseResult(
      delivery: NseComposer.invitation(
        inviter: NseComposer.inviter(event: event, fetched: fetched), roomName: roomName,
        tone: context.meta.tone, tokens: context.tokens(o: event.originServerTs / 1000)),
      outcome: .shown)
  }

  func read(_ receiptTs: Int64, _ context: NseContext) async -> NseResult {
    let delivered = await env.center.delivered().map(\.note)
    var delivery = NseComposer.readNotice(
      names: NseComposer.names(room: context.room, fetched: nil, senderId: nil),
      tokens: context.tokens())
    delivery.removals = DeliveredSweep.identifiersToRemove(
      delivered, reads: [ThreadRead(token: context.t, upToMs: receiptTs)])
    return NseResult(delivery: delivery, outcome: .read)
  }

  func hidden(
    _ context: NseContext, names: NseNames, video: Bool?, outcome: NseOutcome = .hidden
  ) async -> NseResult {
    let thread = await env.center.delivered().filter {
      !ReplyNotSentNotice.isNotice($0.identifier)
        && ($0.t == context.t || $0.threadId == context.t)
    }
    if let newest = thread.max(by: { $0.dateMs < $1.dateMs }) {
      return NseResult(
        delivery: NseComposer.repost(newest, tokens: context.tokens()), outcome: outcome)
    }
    return NseResult(
      delivery: NseComposer.activity(
        names: names, level: context.meta.level, video: video, tokens: context.tokens()),
      outcome: outcome)
  }

  func duplicate(_ context: NseContext) async -> NseResult {
    let copies = await env.center.delivered().filter {
      $0.e == context.e || $0.payloadEventId.map(context.hashing.e) == context.e
    }
    guard let newest = copies.max(by: { $0.dateMs < $1.dateMs }) else {
      let names = NseComposer.names(room: context.room, fetched: nil, senderId: nil)
      return await hidden(context, names: names, video: nil, outcome: .duplicate)
    }
    var delivery = NseComposer.repost(newest, tokens: context.tokens())
    delivery.removals = copies.filter(\.pushed).map(\.identifier)
    return NseResult(delivery: delivery, outcome: .duplicate)
  }

  private func ledgerHas(_ uuid: UUID, _ context: NseContext) -> Bool {
    context.store.ledger().entry(for: uuid) != nil
  }

  private func waitForLedger(_ uuid: UUID, _ context: NseContext, until deadline: Int64) async
    -> Bool
  {
    while env.clock.nowMs() < deadline {
      let slice = min(Self.ledgerPollMs, deadline - env.clock.nowMs())
      await env.clock.wait(ms: Int(slice), wakeOn: [.ringChanged, .callsChanged])
      if ledgerHas(uuid, context) { return true }
    }
    return false
  }
}
