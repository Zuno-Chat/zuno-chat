@preconcurrency import AVFoundation
@preconcurrency import CallKit
import CryptoKit
@preconcurrency import Flutter
import UIKit
import os

enum CallIdentity {
  private static let namespace = UUID(uuidString: "5C2B7E0A-3D4F-4B8E-9A61-2F7C8D0E1B34")!

  static func uuid(roomId: String, callId: String) -> UUID {
    var name = withUnsafeBytes(of: namespace.uuid) { Array($0) }
    name.append(contentsOf: key(roomId: roomId, callId: callId).utf8)
    var hash = Array(Insecure.SHA1.hash(data: name).prefix(16))
    hash[6] = (hash[6] & 0x0F) | 0x50
    hash[8] = (hash[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
        hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
      ))
  }

  static func key(roomId: String, callId: String) -> String {
    "\(roomId)\n\(callId)"
  }

  static func endedReason(_ name: String?) -> CXCallEndedReason {
    switch name {
    case "unanswered": return .unanswered
    case "answeredElsewhere": return .answeredElsewhere
    case "declinedElsewhere": return .declinedElsewhere
    case "failed": return .failed
    default: return .remoteEnded
    }
  }
}

@MainActor
private final class TrackedCall {
  let key: String
  let uuid: UUID
  let roomId: String
  let callId: String
  let callerId: String
  let incoming: Bool
  let reportedAt = Date()
  var name: String
  var isVideo: Bool
  var reportCompleted: Bool
  var pendingEnd: CXCallEndedReason?
  var answered = false
  var adopted = false
  var usesCallKit = true
  var muted = false
  var started = false
  var connectedAt: Date?
  var ownActions: Set<UUID> = []
  var ringTimer: Task<Void, Never>?
  var adoptTimer: Task<Void, Never>?
  var activationTimer: Task<Void, Never>?

  init(
    uuid: UUID, roomId: String, callId: String, callerId: String, incoming: Bool, name: String,
    isVideo: Bool
  ) {
    self.key = CallIdentity.key(roomId: roomId, callId: callId)
    self.uuid = uuid
    self.roomId = roomId
    self.callId = callId
    self.callerId = callerId
    self.incoming = incoming
    self.name = name
    self.isVideo = isVideo
    self.reportCompleted = !incoming
  }

  var arguments: [String: Any] {
    ["roomId": roomId, "callId": callId]
  }

  var ringArguments: [String: Any] {
    ["roomId": roomId, "callId": callId, "callerId": callerId, "isVideo": isVideo]
  }

  func cancelTimers() {
    ringTimer?.cancel()
    adoptTimer?.cancel()
    activationTimer?.cancel()
  }
}

@MainActor
final class CallKitCenter: NSObject {
  static let shared = CallKitCenter()
  nonisolated static let log = Logger(subsystem: "im.zuno.chat", category: "callkit")

  private static let ringLimit: TimeInterval = 55
  nonisolated private static let ignoredRingLimit: TimeInterval = 25
  private static let adoptLimit: TimeInterval = 30
  private static let activationLimit: TimeInterval = 10
  private static let teardownGrace: TimeInterval = 15
  private static let unmuteEchoWindow: TimeInterval = 1.5
  private static let tombstoneLimit = 64
  private static let pendingEventLimit = 32
  private static let ringtoneEnabledKey = "flutter.settings.ringtone_enabled"

  let audio = CallAudio()
  private var provider: CXProvider?
  private lazy var controller = CXCallController(queue: .main)
  private lazy var iconData = UIImage(named: "CallKitIcon")?.pngData()
  private var calls: [String: TrackedCall] = [:]
  private var keysByUUID: [UUID: String] = [:]
  private var tombstones: [String] = []
  private var pendingEvents: [[String: Any]] = []
  private var holds: [UUID: UIBackgroundTaskIdentifier] = [:]
  private var channel: FlutterMethodChannel?
  private var dartReady = false

  var isAvailable: Bool {
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

  nonisolated static func ringtoneSound(_ stored: Any?) -> String? {
    (stored as? Bool) == false ? "silent_ring.caf" : nil
  }

  nonisolated static func systemEndEvent(ringingFor ringing: TimeInterval?, answerWithdrawn: Bool)
    -> String
  {
    if let ringing {
      return ringing < ignoredRingLimit ? "declineCall" : "ringEnded"
    }
    return answerWithdrawn ? "declineCall" : "hangUpCall"
  }

  func setUp() {
    audio.setUp()
    audio.onRouteChange = { [weak self] state in
      self?.emitRoute(state)
    }
    audio.onMediaServicesReset = { [weak self] in
      guard let self, let provider = self.provider else { return }
      provider.configuration = self.makeConfiguration()
    }
  }

  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    dartReady = false
  }

  func detach() {
    channel = nil
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
      .filter { $0.incoming && !$0.answered && $0.reportCompleted }
      .map { ["method": "ringing", "arguments": $0.ringArguments] }
    dartReady = true
    defer { pendingEvents.removeAll() }
    return ringing + pendingEvents
  }

  private func endOrphanedCalls(_ reason: String) {
    let orphaned = calls.values.filter { $0.adopted || ($0.answered && !hasQueuedAnswer($0)) }
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
    if tombstones.contains(key) {
      completion("filtered")
      return
    }
    if calls[key] != nil {
      completion("shown")
      return
    }
    guard isAvailable else {
      completion("unavailable")
      return
    }
    let call = TrackedCall(
      uuid: CallIdentity.uuid(roomId: roomId, callId: callId), roomId: roomId, callId: callId,
      callerId: callerId, incoming: true, name: name, isVideo: isVideo)
    track(call)
    let reply = UncheckedSendable(completion)
    providerForCall().reportNewIncomingCall(with: call.uuid, update: update(for: call)) {
      [weak self] error in
      let refusal = CallKitCenter.refusal(error)
      if let error, let refusal {
        let detail = error.localizedDescription
        CallKitCenter.log.notice(
          "incoming call not shown (\(refusal, privacy: .public)): \(detail, privacy: .public)")
      }
      Task { @MainActor [weak self] in
        reply.value(self?.reported(key, refusal: refusal) ?? "filtered")
      }
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
      uuid: UUID(), roomId: roomId, callId: callId, callerId: "", incoming: false, name: title,
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
    request(action) { [weak self] error in
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
    request(action) { [weak self] error in
      self?.startFailed(key, error, retry: retry)
    }
  }

  func connected(roomId: String, callId: String) {
    guard let call = calls[CallIdentity.key(roomId: roomId, callId: callId)], !call.incoming,
      call.usesCallKit, call.connectedAt == nil
    else { return }
    call.connectedAt = Date()
    if call.started {
      reportConnected(call)
    }
  }

  private func reportConnected(_ call: TrackedCall) {
    provider?.reportOutgoingCall(with: call.uuid, connectedAt: nil)
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
    provider.reportCall(with: call.uuid, updated: update)
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
    request(action) { [weak self] error in
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
    if call.adopted {
      answerForApp(call)
    } else {
      armRingTimer(call)
    }
    return "shown"
  }

  private func reportEnded(_ key: String, _ reason: CXCallEndedReason) {
    guard let call = calls[key] else { return }
    guard call.reportCompleted else {
      call.pendingEnd = reason
      return
    }
    if call.usesCallKit {
      holdBackground(Self.teardownGrace)
      provider?.reportCall(with: call.uuid, endedAt: nil, reason: reason)
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
    if withdrawAnswer(call) {
      emit("ringEnded", call.ringArguments)
    }
    calls.removeValue(forKey: call.key)
    keysByUUID.removeValue(forKey: call.uuid)
    if call.incoming {
      tombstones.append(call.key)
      if tombstones.count > Self.tombstoneLimit {
        tombstones.removeFirst(tombstones.count - Self.tombstoneLimit)
      }
    }
    if calls.isEmpty {
      audio.callsEnded()
    }
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
    request(action) { [weak self] error in
      CallKitCenter.log.notice(
        "mute request refused: \(error.localizedDescription, privacy: .public)")
      guard !muted, let self, let call = self.calls[key], !call.muted else { return }
      call.muted = true
      var arguments = call.arguments
      arguments["muted"] = true
      self.emit("setMuted", arguments)
    }
  }

  private func request(
    _ action: CXAction, onFailure: @escaping @MainActor @Sendable (any Error) -> Void
  ) {
    controller.request(CXTransaction(action: action)) { error in
      guard let error else { return }
      Task { @MainActor in onFailure(error) }
    }
  }

  private func providerForCall() -> CXProvider {
    let configuration = makeConfiguration()
    if let provider {
      provider.configuration = configuration
      return provider
    }
    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: .main)
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
      UserDefaults.standard.object(forKey: Self.ringtoneEnabledKey))
    return configuration
  }

  private func handle(for call: TrackedCall) -> CXHandle {
    CXHandle(type: .generic, value: call.name.isEmpty ? "Zuno" : call.name)
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
    let key = call.key
    call.ringTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.ringLimit * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.ringTimedOut(key)
    }
  }

  private func ringTimedOut(_ key: String) {
    guard let call = calls[key], call.incoming, !call.answered, !call.adopted else { return }
    emit("ringEnded", call.ringArguments)
    reportEnded(key, .unanswered)
  }

  private func armAdoptTimer(_ call: TrackedCall) {
    let key = call.key
    call.adoptTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.adoptLimit * 1_000_000_000))
      guard !Task.isCancelled, let self, let call = self.calls[key], !call.adopted else { return }
      Self.log.error("answered call was never taken over by the app")
      self.emit(self.withdrawAnswer(call) ? "ringEnded" : "hangUpCall", call.ringArguments)
      self.reportEnded(key, .failed)
    }
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

  private func holdBackground(_ seconds: TimeInterval) {
    let token = UUID()
    let task = UIApplication.shared.beginBackgroundTask(withName: "zuno.call.teardown") {
      [weak self] in
      MainActor.assumeIsolated { self?.releaseHold(token) }
    }
    guard task != .invalid else { return }
    holds[token] = task
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      self?.releaseHold(token)
    }
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
    if dartReady, let channel {
      channel.invokeMethod(method, arguments: arguments)
      return
    }
    pendingEvents.append(["method": method, "arguments": arguments])
    if pendingEvents.count > Self.pendingEventLimit {
      pendingEvents.removeFirst(pendingEvents.count - Self.pendingEventLimit)
    }
  }

  private func emitRoute(_ state: CallAudioState) {
    guard dartReady, let channel else { return }
    channel.invokeMethod("audioRouteChanged", arguments: state.arguments)
  }
}

extension CallKitCenter: @preconcurrency CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    Self.log.notice("provider reset with \(self.calls.count, privacy: .public) call(s)")
    guard !calls.isEmpty else { return }
    holdBackground(Self.teardownGrace)
    for call in Array(calls.values) {
      let ringEnded = (call.incoming && !call.answered) || withdrawAnswer(call)
      emit(ringEnded ? "ringEnded" : "hangUpCall", call.ringArguments)
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
    provider.reportOutgoingCall(with: call.uuid, startedConnectingAt: nil)
    call.started = true
    if call.connectedAt != nil {
      call.connectedAt = Date()
      reportConnected(call)
    }
    provider.reportCall(with: call.uuid, updated: update(for: call))
    armActivationWatchdog(call)
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let call = trackedCall(action.callUUID), call.incoming, !call.answered else {
      action.fail()
      return
    }
    audio.prepareForCall(isVideo: call.isVideo)
    call.answered = true
    call.connectedAt = Date()
    call.ringTimer?.cancel()
    if call.ownActions.remove(action.uuid) == nil, !call.adopted {
      emit("answerCall", call.ringArguments)
      armAdoptTimer(call)
    }
    action.fulfill()
    armActivationWatchdog(call)
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = trackedCall(action.callUUID) else {
      action.fulfill()
      return
    }
    holdBackground(Self.teardownGrace)
    if call.ownActions.remove(action.uuid) == nil {
      let ringing =
        call.incoming && !call.answered ? Date().timeIntervalSince(call.reportedAt) : nil
      if let ringing {
        Self.log.notice(
          "unanswered ring ended by the system after \(Int(ringing), privacy: .public) s")
      }
      emit(
        Self.systemEndEvent(ringingFor: ringing, answerWithdrawn: withdrawAnswer(call)),
        call.ringArguments)
    }
    finish(call)
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
