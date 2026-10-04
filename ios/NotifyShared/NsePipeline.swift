import Foundation

protocol NseKeychainReading: Sendable {
  func secrets() -> NotifySecretsRead
}

extension NotifyKeychain: NseKeychainReading {
  func secrets() -> NotifySecretsRead { load(createIfMissing: false) }
}

protocol NseHashing: Sendable {
  func t(_ roomId: String) -> String
  func e(_ value: String) -> String
  func rg(_ callUuid: UUID) -> String
}

protocol NseDeliveredCenter: Sendable {
  func delivered() async -> [NseDelivered]
}

protocol NseSignals: Sendable {
  func post(_ hint: DarwinHint)
  func log(_ event: String, _ fields: [(String, String)])
}

struct NseEnvironment: Sendable {
  let keychain: NseKeychainReading
  let files: @Sendable (NotifySecrets) -> NseFiles
  let hashing: @Sendable (NotifySecrets) -> NseHashing
  let transport: NseTransport
  let decryptor: MegolmDecrypting
  let center: NseDeliveredCenter
  let clock: NseClock
  let defaults: NseDefaults
  let signals: NseSignals
  let processStart: Double
  let footprint: @Sendable () -> UInt64?
  let version: String
  var catchUpPlatform: @Sendable (NseCatchUpPlatform.Sources) -> CatchUpPlatform = {
    NseCatchUpPlatform(sources: $0)
  }
}

struct NseContext: Sendable {
  let push: NsePush
  let roomId: String
  let eventId: String
  let keys: NotifySecrets
  let store: NseStateStore
  let hashing: NseHashing
  let meta: NseMeta
  let t: String
  let e: String
  let start: Int64
  var room: NseRoomFile?
  var catchUpBody: Data? = nil
  var originMs: Int64? = nil

  func tokens(o: Int64? = nil) -> NseTokens {
    NseTokens(t: t, e: e, o: o ?? push.receivedMs / 1000)
  }
}

final class NsePipeline: Sendable {
  static let exportRaceHeartbeatMs: Int64 = 10_000
  static let exportRaceWaitMs = 2000
  static let nothingRingWindowMs: Int64 = 60_000

  let env: NseEnvironment

  init(env: NseEnvironment) {
    self.env = env
  }

  func run(_ push: NsePush, best: @escaping @Sendable (NseDelivery) -> Void) async -> NseResult {
    let start = env.clock.nowMs()
    if push.isTest {
      let result = test()
      record(result, context: nil, start: start, safeMode: false)
      return result
    }
    let crumbs = Breadcrumbs(defaults: env.defaults, processStart: env.processStart)
    let safeMode = crumbs.begin(push.id, nowSeconds: Double(start) / 1000)
    let (result, context) = await process(push, start: start, safeMode: safeMode, best: best)
    crumbs.end(push.id)
    record(result, context: context, start: start, safeMode: safeMode)
    return result
  }

  private func record(_ result: NseResult, context: NseContext?, start: Int64, safeMode: Bool) {
    let now = env.clock.nowMs()
    NseCounters(defaults: env.defaults).record(
      result.outcome, nowMs: now, durationMs: now - start, footprintBytes: env.footprint(),
      readModelAgeMs: context?.meta.heartbeatMs.map { now - $0 })
    var fields: [(String, String)] = [
      ("t", context.map { String($0.t.prefix(8)) } ?? "-"), ("ms", String(now - start)),
    ]
    if let context, let origin = context.originMs {
      fields.append(("lag", String(context.push.receivedMs - origin)))
    }
    fields.append(("safe", safeMode ? "1" : "0"))
    env.signals.log("nse_\(result.outcome.rawValue)", fields)
  }

  private func test() -> NseResult {
    if let keys = Self.ready(env.keychain.secrets()) {
      NseStateStore(files: env.files(keys)).appendMark(NseMark(kind: "test", ts: env.clock.nowMs()))
    }
    return NseResult(delivery: NseComposer.test(), outcome: .test)
  }

  private func process(
    _ push: NsePush, start: Int64, safeMode: Bool, best: @Sendable (NseDelivery) -> Void
  ) async -> (NseResult, NseContext?) {
    guard let roomId = push.roomId, let eventId = push.eventId else {
      return (NseResult(delivery: .passthrough, outcome: .malformed), nil)
    }
    let read = env.keychain.secrets()
    if read == .locked { return (NseResult(delivery: .passthrough, outcome: .bfu), nil) }
    guard let keys = Self.ready(read) else {
      return (NseResult(delivery: .passthrough, outcome: .noMeta), nil)
    }
    let store = NseStateStore(files: env.files(keys))
    if store.state().version != env.version {
      store.updateState { $0.version = env.version }
    }
    guard let meta = store.meta() else {
      return (NseResult(delivery: .passthrough, outcome: .noMeta), nil)
    }
    let hashing = env.hashing(keys)
    let t = hashing.t(roomId)
    var context = NseContext(
      push: push, roomId: roomId, eventId: eventId, keys: keys, store: store, hashing: hashing,
      meta: meta, t: t, e: hashing.e(eventId), start: start,
      room: meta.level == .none ? nil : store.room(token: t, roomId: roomId))
    let names = NseComposer.names(room: context.room, fetched: nil, senderId: nil)
    best(
      NseComposer.floor(
        names: names, level: meta.level, loud: true, tone: meta.tone, tokens: context.tokens()))
    let decided = await decide(&context, safeMode: safeMode, best: best)
    store.recordShown([context.e], in: NotifyFile.shownNse)
    let caughtUp = await catchUp(context, safeMode: safeMode)
    return (await withBadge(decided, context, caughtUp: caughtUp), context)
  }

  private func decide(
    _ context: inout NseContext, safeMode: Bool, best: @Sendable (NseDelivery) -> Void
  ) async -> NseResult {
    if context.meta.level == .none { return nothing(context) }
    if context.store.isShown(context.e) { return await duplicate(context) }
    let baseUrl = context.meta.baseUrl
    guard let credential = context.keys.credential,
      (context.keys.credentialExpiresTs ?? .max) > env.clock.nowMs()
    else { return floor(context, loud: true, outcome: .auth) }
    let (reply, body) = await NseFetchClient(transport: env.transport, clock: env.clock)
      .fetchWithBody(
        baseUrl: baseUrl, credential: credential, roomId: context.roomId,
        eventId: context.eventId)
    switch reply {
    case .ok, .read, .gone: context.catchUpBody = body
    default: break
    }
    switch reply {
    case .ok(let fetched):
      return await fetchedEvent(
        fetched, &context, safeMode: safeMode, credential: credential, baseUrl: baseUrl,
        best: best)
    case .read(let receiptTs): return await read(receiptTs, context)
    case .gone: return floor(context, loud: false, outcome: .gone)
    case .rateLimited: return floor(context, loud: false, outcome: .rateLimited)
    case .unauthorized: return floor(context, loud: true, outcome: .auth)
    case .route: return floor(context, loud: true, outcome: .route)
    case .network: return floor(context, loud: true, outcome: .net)
    case .mismatch: return floor(context, loud: true, outcome: .mismatch)
    }
  }

  private func fetchedEvent(
    _ fetched: NseFetched, _ context: inout NseContext, safeMode: Bool, credential: String,
    baseUrl: String, best: @Sendable (NseDelivery) -> Void
  ) async -> NseResult {
    context.originMs = fetched.event.originServerTs
    let o = fetched.event.originServerTs / 1000
    var event = fetched.event
    let encrypted = event.type == "m.room.encrypted"
    if encrypted {
      if safeMode { return floor(context, loud: true, outcome: .safeMode, fetched: fetched, o: o) }
      switch await decrypt(event, &context) {
      case .event(let plain): event = plain
      case .duplicate: return await duplicate(context)
      case .floor(let outcome):
        return floor(context, loud: true, outcome: outcome, fetched: fetched, o: o)
      }
    }
    let names = NseComposer.names(room: context.room, fetched: fetched, senderId: event.sender)
    let tokens = context.tokens(o: o)
    let now = env.clock.nowMs()
    if let summary = NseClassifier.callSummary(event), event.sender != context.meta.user,
      summary.status == "missed" || summary.status == "declined"
    {
      context.store.appendMark(
        NseMark(
          kind: "summary", room: context.roomId, call: summary.callId, status: summary.status,
          ts: now))
      env.signals.post(.callsChanged)
      if summary.status == "missed" {
        let uuid = CallIdentity.uuid(roomId: context.roomId, callId: summary.callId).uuidString
        if context.store.state().missed.contains(uuid) {
          return await hidden(context, names: names, video: nil)
        }
        context.store.updateState {
          $0.missed = SeenSets.appending(uuid, to: $0.missed, limit: SeenSets.missedLimit)
        }
      }
    }
    switch NseClassifier.classify(event, ownUserId: context.meta.user, nowMs: now) {
    case .hidden:
      let isInvite = NseClassifier.messageType(event) == NseClassifier.callInviteType
      let video = isInvite ? event.content["kind"]?.string == "video" : nil
      return await hidden(context, names: names, video: video)
    case .ring(let callId, let video):
      return await ring(
        callId: callId, video: video, names: names, context: context, credential: credential,
        baseUrl: baseUrl, tokens: tokens, best: best)
    case .invitation(let roomName):
      return await invitation(event: event, fetched: fetched, roomName: roomName, context: context)
    case .verification:
      let sender = names.sender.isEmpty ? names.title : names.sender
      return NseResult(
        delivery: NseComposer.verification(sender: sender, tone: context.meta.tone, tokens: tokens),
        outcome: .shown)
    case .message(let text, let keepsText):
      let loud =
        !context.meta.mentionsOnly
        || isMention(event, fetched: fetched, encrypted: encrypted, context: context)
      return NseResult(
        delivery: NseComposer.message(
          text: text, keepsTextWhenNameOnly: keepsText, names: names, level: context.meta.level,
          loud: loud, tone: context.meta.tone, tokens: tokens),
        outcome: loud ? .shown : .quiet)
    }
  }

  enum Decrypted {
    case event(NseEvent)
    case duplicate
    case floor(NseOutcome)
  }

  private func decrypt(_ envelope: NseEvent, _ context: inout NseContext) async -> Decrypted {
    if let sessionId = Self.megolmSessionId(envelope), context.room?.session(sessionId) == nil,
      let heartbeat = context.meta.heartbeatMs,
      env.clock.nowMs() - heartbeat <= Self.exportRaceHeartbeatMs
    {
      await env.clock.wait(ms: Self.exportRaceWaitMs, wakeOn: [.readModelChanged])
      context.room = context.store.room(token: context.t, roomId: context.roomId)
    }
    return decryptNow(envelope, context)
  }

  static func megolmSessionId(_ envelope: NseEvent) -> String? {
    guard !envelope.redacted,
      envelope.content["algorithm"]?.string == "m.megolm.v1.aes-sha2",
      envelope.content["ciphertext"]?.string != nil
    else { return nil }
    return envelope.content["session_id"]?.string
  }

  func decryptNow(_ envelope: NseEvent, _ context: NseContext) -> Decrypted {
    guard Self.megolmSessionId(envelope) != nil,
      let ciphertext = envelope.content["ciphertext"]?.string,
      let sessionId = envelope.content["session_id"]?.string
    else { return .floor(.utd) }
    guard let session = context.room?.session(sessionId),
      let index = MegolmIndex.messageIndex(ofCiphertext: ciphertext),
      Int(index) >= session.firstIndex
    else {
      recordUtd(context)
      return .floor(.utd)
    }
    if let owner = session.sender, owner != envelope.sender { return .floor(.mismatch) }
    if let claimed = envelope.content["sender_key"]?.string, let known = session.senderKey,
      claimed != known
    {
      return .floor(.mismatch)
    }
    let replayKey = "\(sessionId)|\(index)"
    if context.store.state().replay.contains(replayKey) { return .duplicate }
    guard
      case .plaintext(let text) = env.decryptor.decrypt(
        pickle: session.pickle, userId: context.meta.user, ciphertext: ciphertext)
    else {
      recordUtd(context)
      return .floor(.utd)
    }
    guard let json = NseJson.parse(Data(text.utf8)), json["room_id"]?.string == context.roomId,
      let type = json["type"]?.string
    else { return .floor(.mismatch) }
    context.store.updateState {
      $0.replay = SeenSets.appending(replayKey, to: $0.replay, limit: SeenSets.replayLimit)
    }
    var content = json["content"] ?? .object([:])
    if let relation = envelope.content["m.relates_to"], case .object(var fields) = content {
      fields["m.relates_to"] = relation
      content = .object(fields)
    }
    var event = envelope
    event.type = type
    event.content = content
    return .event(event)
  }

  private func recordUtd(_ context: NseContext) {
    let entry = NseUtd(room: context.roomId, event: context.eventId, ts: env.clock.nowMs())
    context.store.updateState { state in
      state.utd = Array(
        (state.utd.filter { $0.event != entry.event } + [entry]).suffix(SeenSets.utdLimit))
    }
  }

  private func isMention(
    _ event: NseEvent, fetched: NseFetched, encrypted: Bool, context: NseContext
  ) -> Bool {
    guard encrypted else { return fetched.highlight }
    guard let spec = context.meta.mention else { return true }
    return MentionMatcher.isMention(
      content: event.content, sender: event.sender, spec: spec,
      notifiers: context.room?.notifiers ?? [])
  }

  func floor(
    _ context: NseContext, loud: Bool, outcome: NseOutcome, fetched: NseFetched? = nil,
    o: Int64? = nil
  ) -> NseResult {
    let names = NseComposer.names(
      room: context.room, fetched: fetched, senderId: fetched?.event.sender)
    return NseResult(
      delivery: NseComposer.floor(
        names: names, level: context.meta.level, loud: loud, tone: context.meta.tone,
        tokens: context.tokens(o: o)),
      outcome: outcome)
  }

  private func nothing(_ context: NseContext) -> NseResult {
    let now = env.clock.nowMs()
    let ringing = context.store.ledger().calls.contains {
      $0.t == context.t && now - $0.ts <= Self.nothingRingWindowMs
    }
    return NseResult(
      delivery: NseComposer.nothing(
        tokens: context.tokens(), quiet: ringing || context.store.isShown(context.e),
        tone: context.meta.tone),
      outcome: .nothing)
  }

  static func ready(_ read: NotifySecretsRead) -> NotifySecrets? {
    switch read {
    case .ready(let secrets), .created(let secrets): return secrets
    case .locked, .unavailable: return nil
    }
  }

  private func withBadge(
    _ result: NseResult, _ context: NseContext, caughtUp: CatchUpOutcome?
  ) async -> NseResult {
    guard !result.delivery.usesOriginal else { return result }
    var delivery = result.delivery
    let kind = delivery.userInfo["k"]
    let unread = context.meta.unread.map { base in
      caughtUp.map { Array(CatchUpBadge.unread(Set(base), after: $0)) } ?? base
    }
    delivery.badge = NseComposer.badge(
      unread: unread, delivered: await env.center.delivered(),
      removed: Set(delivery.removals).union(caughtUp?.removed ?? []),
      current: (context.t, kind == "msg" || kind == "inv"))
    delivery.category = NotificationCategories.identifier(
      forKind: kind ?? "", level: context.meta.level.rawValue)
    return NseResult(delivery: delivery, outcome: result.outcome)
  }
}
