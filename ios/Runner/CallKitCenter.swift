@preconcurrency import AVFoundation
@preconcurrency import CallKit
@preconcurrency import Flutter
import UIKit
import os

extension CallIdentity {
  static func endedReason(_ name: String?) -> CXCallEndedReason {
    switch name {
    case "unanswered": return .unanswered
    case "answeredElsewhere": return .answeredElsewhere
    case "declinedElsewhere": return .declinedElsewhere
    case "failed": return .failed
    default: return .remoteEnded
    }
  }

  static func endedReason(_ reason: RingEndReason) -> CXCallEndedReason {
    switch reason {
    case .failed: return .failed
    case .unanswered: return .unanswered
    case .remoteEnded: return .remoteEnded
    }
  }
}

enum CallSource: String, Sendable {
  case sync
  case push
  case generic
  case bfu
}

struct CallLedgerChange: Equatable, Sendable {
  let identity: UUID
  let roomId: String
  let state: Ledger.State
  let source: Ledger.Source
}

enum PushReport: Equatable, Sendable {
  case shown(UUID)
  case notShown
  case completed
}

@MainActor
private final class TrackedCall {
  private(set) var key: String
  let uuid: UUID
  private(set) var roomId: String
  private(set) var callId: String
  private(set) var callerId: String
  let incoming: Bool
  var source: CallSource
  let reportedAt = Date()
  var name: String
  var isVideo: Bool
  let ringSeconds: TimeInterval
  var reportCompleted: Bool
  var pendingEnd: CXCallEndedReason?
  var endState: Ledger.State?
  var answered = false
  var adopted = false
  var usesCallKit = true
  var muted = false
  var started = false
  var connectedAt: Date?
  var ownActions: Set<UUID> = []
  var heldAnswer: (any AnswerActionHandle)?
  var ringHold: UUID?
  var ringTimer: Task<Void, Never>?
  var adoptTimer: Task<Void, Never>?
  var activationTimer: Task<Void, Never>?
  var heldAnswerTimer: Task<Void, Never>?

  init(
    uuid: UUID, roomId: String, callId: String, callerId: String, incoming: Bool, name: String,
    isVideo: Bool, source: CallSource = .sync, ringSeconds: TimeInterval = 55
  ) {
    self.key =
      roomId.isEmpty
      ? "generic\n\(uuid.uuidString)" : CallIdentity.key(roomId: roomId, callId: callId)
    self.uuid = uuid
    self.roomId = roomId
    self.callId = callId
    self.callerId = callerId
    self.incoming = incoming
    self.source = source
    self.name = name
    self.isVideo = isVideo
    self.ringSeconds = ringSeconds
    self.reportCompleted = !incoming
  }

  var isBound: Bool { !roomId.isEmpty }

  var identity: UUID? {
    isBound ? CallIdentity.uuid(roomId: roomId, callId: callId) : nil
  }

  var ledgerSource: Ledger.Source { source == .sync ? .sync : .push }

  func bind(roomId: String, callId: String, callerId: String) {
    self.roomId = roomId
    self.callId = callId
    self.callerId = callerId
    key = CallIdentity.key(roomId: roomId, callId: callId)
  }

  var arguments: [String: Any] {
    ["roomId": roomId, "callId": callId]
  }

  var ringArguments: [String: Any] {
    var arguments: [String: Any] = [
      "callerId": callerId, "isVideo": isVideo, "video": isVideo, "uuid": uuid.uuidString,
      "source": source.rawValue,
    ]
    if isBound {
      arguments["roomId"] = roomId
      arguments["callId"] = callId
    }
    return arguments
  }

  func cancelTimers() {
    ringTimer?.cancel()
    adoptTimer?.cancel()
    activationTimer?.cancel()
    heldAnswerTimer?.cancel()
  }
}

@MainActor
final class CallKitCenter: NSObject {
  static let shared = CallKitCenter()
  nonisolated static let log = Logger(subsystem: "im.zuno.chat", category: "callkit")

  nonisolated private static let syncAdoptLimit: TimeInterval = 30
  nonisolated private static let pushAdoptLimit: TimeInterval = 45
  nonisolated private static let ignoredRingLimit: TimeInterval = 25
  private static let activationLimit: TimeInterval = 10
  private static let teardownGrace: TimeInterval = 15
  private static let declineGrace: TimeInterval = 25
  private static let ringGrace: TimeInterval = 30
  private static let heldAnswerMargin: TimeInterval = 2
  private static let unmuteEchoWindow: TimeInterval = 1.5
  private static let tombstoneLimit = 64
  private static let pendingEventLimit = 32
  private static let ringtoneEnabledKey = "flutter.settings.ringtone_enabled"
  static let placeholderHandle = "zuno"

  let audio = CallAudio()
  var onLedger: (@MainActor (CallLedgerChange) -> Void)?
  var roomToken: @MainActor (String) -> String? = { _ in nil }
  var previewLevel: @MainActor () -> PreviewLevel = { .full }
  var isResolved: @MainActor (UUID) -> Bool = { _ in false }
  var ringFlag: @MainActor () -> Bool? = { nil }
  var onUnboundAnswerExpired: (@MainActor (CallSource) -> Void)?

  private let availableOverride: Bool?
  private let makeProvider:
    @MainActor (CXProviderConfiguration, any CXProviderDelegate) -> any CallProviding
  private let requestTransaction:
    @MainActor (CXAction, @escaping @MainActor @Sendable (any Error) -> Void) -> Void
  private var provider: (any CallProviding)?
  private lazy var iconData = UIImage(named: "CallKitIcon")?.pngData()
  private var calls: [String: TrackedCall] = [:]
  private var keysByUUID: [UUID: String] = [:]
  private var tombstones: [(key: String, identity: UUID)] = []
  private var pendingEvents: [[String: Any]] = []
  private var holds: [UUID: UIBackgroundTaskIdentifier] = [:]
  private var declineHolds: [String: UUID] = [:]
  private var sink: (any CallEventSink)?
  private var dartReady = false

  init(
    available: Bool? = nil,
    makeProvider: (
      @MainActor (CXProviderConfiguration, any CXProviderDelegate) -> any CallProviding
    )? = nil,
    requestTransaction: (
      @MainActor (CXAction, @escaping @MainActor @Sendable (any Error) -> Void) -> Void
    )? = nil
  ) {
    availableOverride = available
    self.makeProvider =
      makeProvider ?? { SystemCallProvider(configuration: $0, delegate: $1) }
    let controller = CXCallController(queue: .main)
    self.requestTransaction =
      requestTransaction ?? { action, onFailure in
        controller.request(CXTransaction(action: action)) { error in
          guard let error else { return }
          let box = UncheckedSendable(error)
          Task { @MainActor in onFailure(box.value) }
        }
      }
    super.init()
  }

  var isAvailable: Bool {
    if let availableOverride { return availableOverride }
    #if targetEnvironment(simulator)
      return false
    #else
      return !ProcessInfo.processInfo.isiOSAppOnMac
    #endif
  }

  nonisolated static func refusal(_ error: (any Error)?) -> String? {
    guard let error else { return nil }
    switch (error as? CXErrorCodeIncomingCallError)?.code {
    case .callUUIDAlreadyExists: return nil
    case nil, .unknown, .unentitled: return "unavailable"
    default: return "filtered"
    }
  }

  nonisolated static func ringtoneSound(stored: Any?, flag: Bool?) -> String? {
    if let enabled = stored as? Bool { return enabled ? nil : NseContentFactory.silentRing }
    return flag == false ? NseContentFactory.silentRing : nil
  }

  nonisolated static func systemEndEvent(ringingFor ringing: TimeInterval?, answerWithdrawn: Bool)
    -> String
  {
    if let ringing {
      return ringing < ignoredRingLimit ? "declineCall" : "ringEnded"
    }
    return answerWithdrawn ? "declineCall" : "hangUpCall"
  }

  nonisolated static func adoptLimit(_ source: CallSource) -> TimeInterval {
    source == .sync ? syncAdoptLimit : pushAdoptLimit
  }

  nonisolated static func ledgerState(_ reason: CXCallEndedReason) -> Ledger.State {
    switch reason {
    case .unanswered: return .missed
    case .declinedElsewhere: return .declined
    case .answeredElsewhere: return .answered
    default: return .ended
    }
  }

  func setUp() {
    audio.setUp()
    audio.onRouteChange = { [weak self] state in
      self?.emitRoute(state)
    }
    audio.onMediaServicesReset = { [weak self] in
      guard let self, let provider = self.provider else { return }
      provider.setConfiguration(self.makeConfiguration())
    }
    if isAvailable {
      _ = providerForCall()
    }
  }

  func attach(_ sink: any CallEventSink) {
    self.sink = sink
    dartReady = false
  }

  func detach() {
    sink = nil
    dartReady = false
    endOrphanedCalls("the flutter engine went away")
    audio.releaseMedia()
  }

  func resetForNewDart() {
    dartReady = false
    endOrphanedCalls("dart restarted")
  }

  func takeEvents() -> [[String: Any]] {
    let ringing: [[String: Any]] = calls.values
      .filter { $0.incoming && (!$0.answered || !$0.isBound) && $0.reportCompleted }
      .map { ["method": "ringing", "arguments": $0.ringArguments] }
    dartReady = true
    defer { pendingEvents.removeAll() }
    return ringing + pendingEvents
  }

  func snapshot() -> CallsSnapshot {
    var snapshot = CallsSnapshot()
    for call in calls.values {
      if call.incoming && !call.answered {
        snapshot.ringing = snapshot.ringing ?? call.uuid
      } else {
        snapshot.active = snapshot.active ?? call.uuid
      }
      if let identity = call.identity {
        snapshot.identities[identity] = call.uuid
      }
    }
    snapshot.resolved = Set(tombstones.map(\.identity))
    return snapshot
  }

  private func endOrphanedCalls(_ reason: String) {
    let orphaned = calls.values.filter {
      $0.adopted || ($0.answered && $0.heldAnswer == nil && !hasQueuedAnswer($0))
    }
    guard !orphaned.isEmpty else { return }
    Self.log.error(
      "\(reason, privacy: .public) with \(orphaned.count, privacy: .public) call(s) live")
    for call in orphaned {
      reportEnded(call.key, .failed)
    }
    audio.releaseMedia()
  }

  func reportIncoming(
    roomId: String, callId: String, callerId: String, name: String, isVideo: Bool,
    completion: @escaping (String) -> Void
  ) {
    let key = CallIdentity.key(roomId: roomId, callId: callId)
    if calls[key] != nil {
      completion("shown")
      return
    }
    if tombstoned(key) || isResolved(CallIdentity.uuid(roomId: roomId, callId: callId)) {
      completion("filtered")
      return
    }
    guard isAvailable else {
      completion("unavailable")
      return
    }
    let call = TrackedCall(
      uuid: CallIdentity.uuid(roomId: roomId, callId: callId), roomId: roomId, callId: callId,
      callerId: callerId, incoming: true, name: CallerName.shown(name, level: previewLevel()),
      isVideo: isVideo)
    track(call)
    let reply = UncheckedSendable(completion)
    providerForCall().reportNewIncomingCall(call.uuid, update: update(for: call)) {
      [weak self] error in
      let refusal = CallKitCenter.refusal(error)
      if let error, let refusal {
        CallKitCenter.log.notice(
          "incoming call not shown (\(refusal, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
      }
      reply.value(self?.reported(key, refusal: refusal) ?? "filtered")
    }
  }

  func reportPush(
    _ action: RingAction, completion: @escaping @MainActor @Sendable (PushReport) -> Void
  ) {
    switch action {
    case .complete:
      completion(.completed)
    case .ring(let ring):
      let call = TrackedCall(
        uuid: ring.uuid, roomId: ring.roomId, callId: ring.callId, callerId: ring.callerId,
        incoming: true, name: ring.name, isVideo: ring.video, source: .push,
        ringSeconds: TimeInterval(ring.ringSeconds))
      reportTracked(call, completion: completion)
    case .generic(let ring):
      let call = TrackedCall(
        uuid: ring.uuid, roomId: "", callId: "", callerId: "", incoming: true,
        name: CallerName.generic, isVideo: false,
        source: ring.beforeFirstUnlock ? .bfu : .generic,
        ringSeconds: TimeInterval(ring.ringSeconds))
      reportTracked(call, completion: completion)
    case .update(let uuid, let name, let video, let reportAgain):
      guard let call = trackedCall(uuid) else {
        reportPlaceholder(uuid, endingWith: .remoteEnded, completion: completion)
        return
      }
      if reportAgain {
        let provider = providerForCall()
        provider.reportNewIncomingCall(uuid, update: update(for: call)) { [weak self] error in
          if error == nil {
            if let self, let tracked = self.trackedCall(uuid) {
              self.reportEnded(tracked.key, .remoteEnded)
            } else {
              provider.reportEnded(uuid, reason: .remoteEnded)
            }
          }
          completion(.completed)
        }
      } else {
        completion(.completed)
      }
      applyUpdate(to: call, name: name, isVideo: video, authoritative: false)
    case .duplicate(let uuid):
      reportPlaceholder(uuid, endingWith: .remoteEnded, completion: completion)
    case .reportThenEnd(let uuid, let reason):
      reportPlaceholder(
        uuid, endingWith: CallIdentity.endedReason(reason), completion: completion)
    }
  }

  private func reportTracked(
    _ call: TrackedCall, completion: @escaping @MainActor @Sendable (PushReport) -> Void
  ) {
    guard isAvailable else {
      completion(.notShown)
      return
    }
    track(call)
    let key = call.key
    providerForCall().reportNewIncomingCall(call.uuid, update: update(for: call)) {
      [weak self] error in
      let refusal = CallKitCenter.refusal(error)
      if let error, let refusal {
        CallKitCenter.log.notice(
          "pushed call not shown (\(refusal, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
      }
      let outcome = self?.reported(key, refusal: refusal) ?? "filtered"
      completion(outcome == "shown" ? .shown(call.uuid) : .notShown)
    }
  }

  private func reportPlaceholder(
    _ uuid: UUID, endingWith reason: CXCallEndedReason,
    completion: @escaping @MainActor @Sendable (PushReport) -> Void
  ) {
    guard isAvailable else {
      completion(.completed)
      return
    }
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: Self.placeholderHandle)
    update.localizedCallerName = CallerName.generic
    update.hasVideo = false
    let provider = providerForCall()
    provider.reportNewIncomingCall(uuid, update: update) { [weak self] error in
      if error == nil {
        if let self, let call = self.trackedCall(uuid) {
          self.reportEnded(call.key, .remoteEnded)
        } else {
          provider.reportEnded(uuid, reason: reason)
        }
      }
      completion(.completed)
    }
  }

  func updateIncoming(roomId: String, callId: String, name: String, isVideo: Bool) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)], call.incoming
    else { return }
    applyUpdate(to: call, name: name, isVideo: isVideo, authoritative: true)
  }

  private func applyUpdate(
    to call: TrackedCall, name: String, isVideo: Bool, authoritative: Bool
  ) {
    let shown = CallerName.shown(name, level: previewLevel())
    var changed = false
    if shown != call.name && (authoritative || call.name == CallerName.generic) {
      call.name = shown
      changed = true
    }
    if isVideo && !call.isVideo {
      call.isVideo = true
      changed = true
    }
    guard changed, call.usesCallKit, call.reportCompleted, let provider else { return }
    provider.reportUpdate(call.uuid, update(for: call))
  }

  @discardableResult
  func bind(
    uuid: UUID, roomId: String, callId: String, callerId: String, name: String, isVideo: Bool
  ) -> Bool {
    guard let call = trackedCall(uuid), call.incoming, !call.isBound else { return false }
    let key = CallIdentity.key(roomId: roomId, callId: callId)
    let identity = CallIdentity.uuid(roomId: roomId, callId: callId)
    if calls[key] != nil || tombstoned(key) || isResolved(identity) {
      reportEnded(call.key, .remoteEnded)
      return false
    }
    calls.removeValue(forKey: call.key)
    call.bind(roomId: roomId, callId: callId, callerId: callerId)
    call.source = .push
    track(call)
    applyUpdate(to: call, name: name, isVideo: isVideo, authoritative: true)
    record(call, call.answered ? .answered : .ringing)
    if call.answered, call.heldAnswer != nil, !call.adopted {
      emit("answerCall", call.ringArguments)
    }
    return true
  }

  func treatAsGeneric(uuid: UUID) {
    guard let call = trackedCall(uuid), !call.isBound, call.source == .bfu else { return }
    call.source = .generic
  }

  func endUnbound(uuid: UUID) {
    guard let call = trackedCall(uuid), !call.isBound else { return }
    reportEnded(call.key, .failed)
  }

  func declineSent(roomId: String, callId: String) {
    guard
      let token = declineHolds.removeValue(forKey: CallIdentity.key(roomId: roomId, callId: callId))
    else { return }
    releaseHold(token)
  }

  func endAll(reason: CXCallEndedReason) {
    for call in Array(calls.values) {
      reportEnded(call.key, reason)
    }
  }

  func endIncoming(roomId: String, callId: String, reason: CXCallEndedReason) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)], call.incoming,
      !call.answered
    else { return }
    reportEnded(call.key, reason)
  }

  func begin(roomId: String, callId: String, title: String, isVideo: Bool) -> [String: Any] {
    let key = CallIdentity.key(roomId: roomId, callId: callId)
    if let call = calls[key] {
      adopt(call)
      if call.incoming, !call.answered, call.reportCompleted, call.usesCallKit {
        answerForApp(call)
      }
      return ["muted": call.muted]
    }
    let call = TrackedCall(
      uuid: CallIdentity.uuid(roomId: roomId, callId: callId), roomId: roomId, callId: callId,
      callerId: "", incoming: false, name: CallerName.shown(title, level: previewLevel()),
      isVideo: isVideo)
    call.adopted = true
    track(call)
    guard isAvailable else {
      call.usesCallKit = false
      audio.beginSelfManaged(isVideo: isVideo)
      return ["muted": false]
    }
    requestStart(call, retry: true)
    return ["muted": false]
  }

  private func answerForApp(_ call: TrackedCall) {
    call.ringTimer?.cancel()
    let key = call.key
    let action = CXAnswerCallAction(call: call.uuid)
    call.ownActions.insert(action.uuid)
    requestTransaction(action) { [weak self] error in
      CallKitCenter.log.error(
        "in-app answer refused: \(error.localizedDescription, privacy: .public)")
      guard let self, let call = self.calls[key] else { return }
      self.emit("callFailed", call.arguments)
      self.reportEnded(key, .failed)
    }
  }

  private func requestStart(_ call: TrackedCall, retry: Bool) {
    _ = providerForCall()
    let key = call.key
    let action = CXStartCallAction(call: call.uuid, handle: handle(for: call))
    action.isVideo = call.isVideo
    call.ownActions.insert(action.uuid)
    requestTransaction(action) { [weak self] error in
      self?.startFailed(key, error, retry: retry)
    }
  }

  func connected(roomId: String, callId: String) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)] else { return }
    if call.incoming {
      fulfillHeldAnswer(call)
      return
    }
    guard call.usesCallKit, call.connectedAt == nil else { return }
    call.connectedAt = Date()
    if call.started {
      reportConnected(call)
    }
  }

  private func reportConnected(_ call: TrackedCall) {
    provider?.reportOutgoingConnected(call.uuid)
    if call.muted {
      requestMute(call, true)
    }
  }

  func setMuted(roomId: String, callId: String, muted: Bool) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)], call.muted != muted
    else { return }
    call.muted = muted
    if call.usesCallKit {
      requestMute(call, muted)
    }
  }

  func upgradeToVideo(roomId: String, callId: String) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)], !call.isVideo else {
      return
    }
    call.isVideo = true
    guard call.usesCallKit, call.reportCompleted, let provider else { return }
    let update = CXCallUpdate()
    update.hasVideo = true
    provider.reportUpdate(call.uuid, update)
  }

  func end(roomId: String, callId: String, reason: CXCallEndedReason, byUser: Bool) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)] else { return }
    guard call.usesCallKit else {
      finish(call)
      return
    }
    guard byUser, call.reportCompleted else {
      reportEnded(call.key, reason)
      return
    }
    releaseMute(call)
    let key = call.key
    let action = CXEndCallAction(call: call.uuid)
    call.ownActions.insert(action.uuid)
    requestTransaction(action) { [weak self] error in
      CallKitCenter.log.error(
        "end request refused: \(error.localizedDescription, privacy: .public)")
      self?.reportEnded(key, reason)
    }
  }

  private func track(_ call: TrackedCall) {
    calls[call.key] = call
    keysByUUID[call.uuid] = call.key
  }

  private func trackedCall(_ uuid: UUID) -> TrackedCall? {
    keysByUUID[uuid].flatMap { calls[$0] }
  }

  private func tombstoned(_ key: String) -> Bool {
    tombstones.contains { $0.key == key }
  }

  private func reported(_ key: String, refusal: String?) -> String {
    guard let call = calls[key] else { return "filtered" }
    if let refusal {
      let cancelled = call.pendingEnd != nil
      finish(call)
      return cancelled ? "filtered" : refusal
    }
    call.reportCompleted = true
    if let reason = call.pendingEnd {
      reportEnded(key, reason)
      return "filtered"
    }
    record(call, .ringing)
    if call.adopted {
      answerForApp(call)
    } else {
      armRingTimer(call)
    }
    if call.source != .sync {
      call.ringHold = holdBackground(Self.ringGrace)
      emitLive("ringing", call.ringArguments)
    }
    return "shown"
  }

  private func reportEnded(_ key: String, _ reason: CXCallEndedReason) {
    guard let call = calls[key] else { return }
    guard call.reportCompleted else {
      call.pendingEnd = reason
      return
    }
    if call.endState == nil {
      call.endState = call.answered && reason != .failed ? .ended : Self.ledgerState(reason)
    }
    if call.usesCallKit {
      holdBackground(Self.teardownGrace)
      provider?.reportEnded(call.uuid, reason: reason)
    }
    finish(call)
  }

  private func releaseMute(_ call: TrackedCall) {
    guard call.muted, !call.incoming || call.answered else { return }
    call.muted = false
    requestMute(call, false)
  }

  private func finish(_ call: TrackedCall) {
    guard calls[call.key] === call else { return }
    call.cancelTimers()
    if let held = call.heldAnswer {
      call.heldAnswer = nil
      held.fail()
    }
    if let hold = call.ringHold {
      call.ringHold = nil
      releaseHold(hold)
    }
    if withdrawAnswer(call) {
      emit("ringEnded", call.ringArguments)
    }
    calls.removeValue(forKey: call.key)
    keysByUUID.removeValue(forKey: call.uuid)
    if call.incoming {
      record(call, call.endState ?? (call.answered ? .ended : .missed))
      if let identity = call.identity {
        tombstones.append((key: call.key, identity: identity))
        if tombstones.count > Self.tombstoneLimit {
          tombstones.removeFirst(tombstones.count - Self.tombstoneLimit)
        }
      }
    }
    if calls.isEmpty {
      audio.callsEnded()
    }
  }

  private func record(_ call: TrackedCall, _ state: Ledger.State) {
    guard call.incoming, let identity = call.identity else { return }
    onLedger?(
      CallLedgerChange(
        identity: identity, roomId: call.roomId, state: state, source: call.ledgerSource))
  }

  private func adopt(_ call: TrackedCall) {
    call.adopted = true
    call.adoptTimer?.cancel()
  }

  private func startFailed(_ key: String, _ error: any Error, retry: Bool) {
    guard let call = calls[key] else { return }
    Self.log.error("start request refused: \(error.localizedDescription, privacy: .public)")
    let brokenProvider =
      (error as? CXErrorCodeRequestTransactionError)?.code == .unknownCallProvider
    if brokenProvider, retry, calls.count == 1 {
      provider?.invalidate()
      provider = nil
      requestStart(call, retry: false)
      return
    }
    emit("callFailed", call.arguments)
    finish(call)
  }

  private func requestMute(_ call: TrackedCall, _ muted: Bool) {
    let key = call.key
    let action = CXSetMutedCallAction(call: call.uuid, muted: muted)
    call.ownActions.insert(action.uuid)
    requestTransaction(action) { [weak self] error in
      CallKitCenter.log.notice(
        "mute request refused: \(error.localizedDescription, privacy: .public)")
      guard !muted, let self, let call = self.calls[key], !call.muted else { return }
      call.muted = true
      var arguments = call.arguments
      arguments["muted"] = true
      self.emit("setMuted", arguments)
    }
  }

  private func providerForCall() -> any CallProviding {
    let configuration = makeConfiguration()
    if let provider {
      provider.setConfiguration(configuration)
      return provider
    }
    let provider = makeProvider(configuration, self)
    self.provider = provider
    return provider
  }

  private func makeConfiguration() -> CXProviderConfiguration {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 2
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = false
    configuration.iconTemplateImageData = iconData
    configuration.ringtoneSound = Self.ringtoneSound(
      stored: UserDefaults.standard.object(forKey: Self.ringtoneEnabledKey), flag: ringFlag())
    return configuration
  }

  private func handle(for call: TrackedCall) -> CXHandle {
    let token = call.isBound ? roomToken(call.roomId) : nil
    return CXHandle(type: .generic, value: token ?? Self.placeholderHandle)
  }

  private func update(for call: TrackedCall) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.remoteHandle = handle(for: call)
    update.localizedCallerName = call.name
    update.hasVideo = call.isVideo
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    return update
  }

  private func armRingTimer(_ call: TrackedCall) {
    let uuid = call.uuid
    let seconds = call.ringSeconds
    call.ringTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      guard !Task.isCancelled, let self, let call = self.trackedCall(uuid) else { return }
      self.ringTimedOut(call.key)
    }
  }

  private func ringTimedOut(_ key: String) {
    guard let call = calls[key], call.incoming, !call.answered, !call.adopted else { return }
    if call.isBound {
      emit("ringEnded", call.ringArguments)
    }
    call.endState = .missed
    reportEnded(key, .unanswered)
  }

  private func armAdoptTimer(_ call: TrackedCall) {
    let uuid = call.uuid
    let limit = Self.adoptLimit(call.source)
    call.adoptTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
      guard !Task.isCancelled, let self, let call = self.trackedCall(uuid), !call.adopted else {
        return
      }
      Self.log.error("answered call was never taken over by the app")
      if call.isBound {
        self.emit(self.withdrawAnswer(call) ? "ringEnded" : "hangUpCall", call.ringArguments)
      }
      self.reportEnded(call.key, .failed)
    }
  }

  private func holdAnswer(_ action: any AnswerActionHandle, for call: TrackedCall) {
    call.heldAnswer = action
    let uuid = call.uuid
    let wait = max(0, action.timeoutDate.timeIntervalSinceNow - Self.heldAnswerMargin)
    call.heldAnswerTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      guard !Task.isCancelled, let self, let call = self.trackedCall(uuid) else { return }
      self.heldAnswerDeadline(call)
    }
  }

  private func heldAnswerDeadline(_ call: TrackedCall) {
    guard call.heldAnswer != nil else { return }
    if call.isBound {
      fulfillHeldAnswer(call)
      return
    }
    Self.log.error("an answered ring never learned its call")
    onUnboundAnswerExpired?(call.source)
    reportEnded(call.key, .failed)
  }

  private func fulfillHeldAnswer(_ call: TrackedCall) {
    guard let held = call.heldAnswer else { return }
    call.heldAnswer = nil
    call.heldAnswerTimer?.cancel()
    held.fulfill()
    armActivationWatchdog(call)
  }

  private func armActivationWatchdog(_ call: TrackedCall) {
    guard !audio.isActive else { return }
    let key = call.key
    call.activationTimer?.cancel()
    call.activationTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.activationLimit * 1_000_000_000))
      guard !Task.isCancelled, let self, let call = self.calls[key], !self.audio.isActive else {
        return
      }
      Self.log.error("the system never activated call audio")
      self.emit("callFailed", call.arguments)
      self.reportEnded(key, .failed)
    }
  }

  @discardableResult
  private func holdBackground(_ seconds: TimeInterval) -> UUID? {
    let token = UUID()
    let task = UIApplication.shared.beginBackgroundTask(withName: "zuno.call.teardown") {
      [weak self] in
      MainActor.assumeIsolated { self?.releaseHold(token) }
    }
    guard task != .invalid else { return nil }
    holds[token] = task
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      self?.releaseHold(token)
    }
    return token
  }

  private func releaseHold(_ token: UUID) {
    guard let task = holds.removeValue(forKey: token) else { return }
    UIApplication.shared.endBackgroundTask(task)
  }

  private func isQueuedAnswer(_ event: [String: Any], _ call: TrackedCall) -> Bool {
    guard event["method"] as? String == "answerCall",
      let arguments = event["arguments"] as? [String: Any]
    else { return false }
    return arguments["roomId"] as? String == call.roomId
      && arguments["callId"] as? String == call.callId
  }

  private func hasQueuedAnswer(_ call: TrackedCall) -> Bool {
    pendingEvents.contains { isQueuedAnswer($0, call) }
  }

  private func withdrawAnswer(_ call: TrackedCall) -> Bool {
    let before = pendingEvents.count
    pendingEvents.removeAll { isQueuedAnswer($0, call) }
    return pendingEvents.count != before
  }

  private func emit(_ method: String, _ arguments: [String: Any]) {
    if dartReady, let sink {
      sink.send(method, arguments)
      return
    }
    pendingEvents.append(["method": method, "arguments": arguments])
    if pendingEvents.count > Self.pendingEventLimit {
      pendingEvents.removeFirst(pendingEvents.count - Self.pendingEventLimit)
    }
  }

  private func emitLive(_ method: String, _ arguments: [String: Any]) {
    guard dartReady, let sink else { return }
    sink.send(method, arguments)
  }

  private func emitRoute(_ state: CallAudioState) {
    emitLive("audioRouteChanged", state.arguments)
  }

  func answer(_ uuid: UUID, action: any AnswerActionHandle) {
    guard let call = trackedCall(uuid), call.incoming, !call.answered else {
      action.fail()
      return
    }
    audio.prepareForCall(isVideo: call.isVideo)
    call.answered = true
    call.connectedAt = Date()
    call.ringTimer?.cancel()
    if let hold = call.ringHold {
      call.ringHold = nil
      releaseHold(hold)
    }
    record(call, .answered)
    let own = call.ownActions.remove(action.actionId) != nil
    guard !own, !call.adopted else {
      action.fulfill()
      armActivationWatchdog(call)
      return
    }
    armAdoptTimer(call)
    guard call.source != .sync else {
      emit("answerCall", call.ringArguments)
      action.fulfill()
      armActivationWatchdog(call)
      return
    }
    holdAnswer(action, for: call)
    if call.isBound {
      emit("answerCall", call.ringArguments)
    }
  }

  func systemEnd(_ uuid: UUID, actionId: UUID) {
    guard let call = trackedCall(uuid) else { return }
    holdBackground(Self.teardownGrace)
    if call.ownActions.remove(actionId) == nil {
      let ringing =
        call.incoming && !call.answered ? Date().timeIntervalSince(call.reportedAt) : nil
      if let ringing {
        Self.log.notice(
          "unanswered ring ended by the system after \(Int(ringing), privacy: .public) s")
      }
      let event = Self.systemEndEvent(ringingFor: ringing, answerWithdrawn: withdrawAnswer(call))
      if ringing != nil {
        call.endState = event == "declineCall" ? .declined : .missed
      }
      if call.isBound {
        if event == "declineCall", let hold = holdBackground(Self.declineGrace) {
          declineHolds[call.key] = hold
        }
        emit(event, call.ringArguments)
      }
    }
    finish(call)
  }
}

extension CallKitCenter: @preconcurrency CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    Self.log.notice("provider reset with \(self.calls.count, privacy: .public) call(s)")
    guard !calls.isEmpty else { return }
    holdBackground(Self.teardownGrace)
    for call in Array(calls.values) {
      let ringEnded = (call.incoming && !call.answered) || withdrawAnswer(call)
      if call.isBound {
        emit(ringEnded ? "ringEnded" : "hangUpCall", call.ringArguments)
      }
      call.endState = .ended
      finish(call)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard let call = trackedCall(action.callUUID), !call.incoming else {
      action.fail()
      return
    }
    call.ownActions.remove(action.uuid)
    audio.prepareForCall(isVideo: call.isVideo)
    action.fulfill()
    self.provider?.reportOutgoingStarted(call.uuid)
    call.started = true
    if call.connectedAt != nil {
      call.connectedAt = Date()
      reportConnected(call)
    }
    self.provider?.reportUpdate(call.uuid, update(for: call))
    armActivationWatchdog(call)
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    answer(action.callUUID, action: action)
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    systemEnd(action.callUUID, actionId: action.uuid)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let call = trackedCall(action.callUUID) else {
      action.fulfill()
      return
    }
    if call.ownActions.remove(action.uuid) != nil || action.isMuted == call.muted {
      action.fulfill()
      return
    }
    if !action.isMuted, let connectedAt = call.connectedAt,
      Date().timeIntervalSince(connectedAt) < Self.unmuteEchoWindow
    {
      action.fulfill()
      requestMute(call, true)
      return
    }
    call.muted = action.isMuted
    var arguments = call.arguments
    arguments["muted"] = action.isMuted
    emit("setMuted", arguments)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    if action.isOnHold {
      action.fail()
    } else {
      action.fulfill()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
    action.fail()
  }

  func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
    action.fail()
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    Self.log.error(
      "CallKit action timed out: \(String(describing: type(of: action)), privacy: .public)")
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    for call in calls.values {
      call.activationTimer?.cancel()
    }
    audio.didActivate(audioSession)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    audio.didDeactivate(audioSession)
  }
}
