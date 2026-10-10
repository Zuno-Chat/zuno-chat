@preconcurrency import AVFoundation
import Foundation
@preconcurrency import WebRTC
@preconcurrency import flutter_webrtc
import os

enum CallAudioRoute: String, CaseIterable {
  case earpiece
  case speaker
  case wiredHeadset
  case bluetooth
}

struct CallAudioState: Equatable {
  let route: CallAudioRoute
  let headsets: Set<CallAudioRoute>

  var arguments: [String: Any] {
    [
      "route": route.rawValue,
      "headsets": CallAudioRoute.allCases.filter(headsets.contains).map(\.rawValue),
    ]
  }
}

enum CallAudioInputChoice: Equatable {
  case unchanged
  case clear
  case prefer(AVAudioSession.Port)
}

enum CallAudioRouting {
  static let callOptions: AVAudioSession.CategoryOptions = [
    .allowBluetoothHFP, .allowBluetoothA2DP,
  ]
  static let foreignOptions: AVAudioSession.CategoryOptions = [
    .defaultToSpeaker, .mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers,
  ]

  static func route(forOutput port: AVAudioSession.Port) -> CallAudioRoute {
    switch port {
    case .builtInReceiver: return .earpiece
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio: return .bluetooth
    case .headphones, .usbAudio, .lineOut: return .wiredHeadset
    default: return .speaker
    }
  }

  static func headset(for port: AVAudioSession.Port) -> CallAudioRoute? {
    switch port {
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio: return .bluetooth
    case .headphones, .headsetMic, .usbAudio, .lineOut: return .wiredHeadset
    default: return nil
    }
  }

  static func inputPorts(for route: CallAudioRoute) -> [AVAudioSession.Port] {
    switch route {
    case .bluetooth: return [.bluetoothHFP, .bluetoothLE, .carAudio]
    case .wiredHeadset: return [.headsetMic, .usbAudio]
    case .earpiece, .speaker: return [.builtInMic]
    }
  }

  static func state(outputs: [AVAudioSession.Port], inputs: [AVAudioSession.Port])
    -> CallAudioState
  {
    let route = outputs.first.map(route(forOutput:)) ?? .earpiece
    let headsets = Set((outputs + inputs).compactMap(headset(for:)))
    return CallAudioState(route: route, headsets: headsets)
  }

  static func isCallConfiguration(
    category: AVAudioSession.Category, mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions
  ) -> Bool {
    category == .playAndRecord && mode == .voiceChat && options.isSuperset(of: callOptions)
      && options.isDisjoint(with: foreignOptions)
  }

  static func startingRoute(wanted: CallAudioRoute?, isVideo: Bool, headsets: Set<CallAudioRoute>)
    -> CallAudioRoute?
  {
    if let wanted {
      return wanted
    }
    return isVideo && headsets.isEmpty ? .speaker : nil
  }

  static func restoredRoute(
    reported: CallAudioRoute?, wanted: CallAudioRoute?, isVideo: Bool,
    headsets: Set<CallAudioRoute>
  ) -> CallAudioRoute? {
    reported ?? startingRoute(wanted: wanted, isVideo: isVideo, headsets: headsets)
  }

  static func preferredInput(for route: CallAudioRoute, available: [AVAudioSession.Port])
    -> CallAudioInputChoice
  {
    switch route {
    case .speaker:
      return .unchanged
    case .earpiece:
      let headsetInput = available.contains { headset(for: $0) != nil }
      return headsetInput && available.contains(.builtInMic) ? .prefer(.builtInMic) : .clear
    case .bluetooth, .wiredHeadset:
      let ports = inputPorts(for: route)
      guard let port = available.first(where: { ports.contains($0) }) else { return .unchanged }
      return .prefer(port)
    }
  }
}

struct UncheckedSendable<Value>: @unchecked Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }
}

final class CallAudioEngineGate: @unchecked Sendable {
  private let queue = DispatchQueue(label: "im.zuno.calls.audio-gate")
  private var factory: RTCPeerConnectionFactory?
  private var module: RTCAudioDeviceModule?
  private var available = false
  private var applied: Bool?

  func attach(_ factory: RTCPeerConnectionFactory?) {
    let box = UncheckedSendable(factory)
    queue.async { [self] in
      if self.factory !== box.value {
        self.factory = box.value
        module = box.value?.audioDeviceModule
        applied = nil
      }
      apply()
    }
  }

  func setAvailable(_ value: Bool) {
    queue.async { [self] in
      available = value
      apply()
    }
  }

  private func apply() {
    guard let module, applied != available else { return }
    let availability = RTCAudioEngineAvailability(
      isInputAvailable: ObjCBool(available), isOutputAvailable: ObjCBool(available))
    let result = module.setEngineAvailability(availability)
    applied = result == 0 ? available : nil
    if result != 0 {
      CaughtErrors.record(
        available ? "call audio engine enable" : "call audio engine disable",
        NSError(domain: "org.webrtc.RTCAudioDeviceModule", code: result))
    }
  }
}

@MainActor
final class CallRingback {
  private var player: AVAudioPlayer?
  private var wanted = false
  private var sessionActive = false
  private lazy var tone = Self.ringbackTone()

  func setWanted(_ value: Bool) {
    wanted = value
    update()
  }

  func setSessionActive(_ value: Bool) {
    sessionActive = value
    update()
  }

  func restart() {
    player?.stop()
    player = nil
    update()
  }

  private func update() {
    guard wanted, sessionActive else {
      player?.stop()
      player = nil
      return
    }
    if player == nil {
      player = CaughtErrors.attempt("call ringback player") {
        try AVAudioPlayer(data: tone, fileTypeHint: AVFileType.wav.rawValue)
      }
      player?.numberOfLoops = -1
    }
    if player?.isPlaying == false {
      player?.play()
    }
  }

  nonisolated static func ringbackTone(sampleRate: Int = 16_000) -> Data {
    let toneSamples = sampleRate
    let totalSamples = sampleRate * 5
    let fadeSamples = sampleRate / 50
    var pcm = Data(capacity: totalSamples * 2)
    for index in 0..<totalSamples {
      var value = 0.0
      if index < toneSamples {
        let edge = Double(min(index, toneSamples - 1 - index))
        let envelope = min(1, edge / Double(fadeSamples))
        value = sin(2 * .pi * 425 * Double(index) / Double(sampleRate)) * 0.3 * envelope
      }
      appendLittleEndian(Int16(value * Double(Int16.max)), to: &pcm)
    }
    var wav = Data()
    wav.append(contentsOf: Array("RIFF".utf8))
    appendLittleEndian(UInt32(36 + pcm.count), to: &wav)
    wav.append(contentsOf: Array("WAVEfmt ".utf8))
    appendLittleEndian(UInt32(16), to: &wav)
    appendLittleEndian(UInt16(1), to: &wav)
    appendLittleEndian(UInt16(1), to: &wav)
    appendLittleEndian(UInt32(sampleRate), to: &wav)
    appendLittleEndian(UInt32(sampleRate * 2), to: &wav)
    appendLittleEndian(UInt16(2), to: &wav)
    appendLittleEndian(UInt16(16), to: &wav)
    wav.append(contentsOf: Array("data".utf8))
    appendLittleEndian(UInt32(pcm.count), to: &wav)
    wav.append(pcm)
    return wav
  }

  nonisolated private static func appendLittleEndian<T: FixedWidthInteger>(
    _ value: T, to data: inout Data
  ) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
  }
}

@MainActor
final class CallAudio {
  nonisolated static let log = Logger(subsystem: "im.zuno.chat", category: "call-audio")

  nonisolated static func isSessionError(_ error: any Error, _ code: AVAudioSession.ErrorCode)
    -> Bool
  {
    let bridged = error as NSError
    return bridged.domain == NSOSStatusErrorDomain && bridged.code == code.rawValue
  }

  let ringback = CallRingback()
  var onRouteChange: ((CallAudioState) -> Void)?
  var onMediaServicesReset: (() -> Void)?
  private(set) var isActive = false
  private let gate = CallAudioEngineGate()
  private weak var webRTC: FlutterWebRTCPlugin?
  private var observers: [NSObjectProtocol] = []
  private var forwardedActivation = false
  private var selfManaged = false
  private var inCall = false
  private var videoCall = false
  private var saved:
    (
      category: AVAudioSession.Category, mode: AVAudioSession.Mode,
      options: AVAudioSession.CategoryOptions
    )?
  private var wantedRoute: CallAudioRoute?
  private var reported: CallAudioState?
  private var rebalance: Task<Void, Never>?

  func setUp() {
    FlutterWebRTCPlugin.setAudioSessionManagementEnabled(false)
    let rtc = RTCAudioSession.sharedInstance()
    rtc.useManualAudio = true
    rtc.isAudioEnabled = false
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] notification in
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        MainActor.assumeIsolated { self?.routeChanged(reason) }
      })
    observers.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.mediaServicesWereReset() }
      })
  }

  func adoptRegisteredWebRTC() {
    if let plugin = FlutterWebRTCPlugin.sharedSingleton() {
      webRTC = plugin
      gate.attach(nil)
    }
  }

  func armEngine() {
    let plugin = webRTC ?? FlutterWebRTCPlugin.sharedSingleton()
    gate.attach(plugin?.peerConnectionFactory)
    gate.setAvailable(isActive)
  }

  func prepareForCall(isVideo: Bool) {
    videoCall = videoCall || isVideo
    if !inCall {
      inCall = true
      rebalance?.cancel()
      let session = AVAudioSession.sharedInstance()
      if !isActive {
        do {
          try session.setActive(false)
        } catch let error where Self.isSessionError(error, .isBusy) {
          Self.log.notice("call audio reset: the session is busy")
        } catch {
          CaughtErrors.record("call audio reset", error)
        }
      }
      if saved == nil {
        saved = (session.category, session.mode, session.categoryOptions)
      }
    }
    configure()
  }

  func didActivate(_ session: AVAudioSession) {
    if !forwardedActivation {
      RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
      forwardedActivation = true
    }
    guard inCall else {
      isActive = true
      scheduleRebalance()
      return
    }
    configure()
    activated()
  }

  func didDeactivate(_ session: AVAudioSession) {
    deactivated()
    if forwardedActivation {
      RTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
      forwardedActivation = false
    }
    restoreIfIdle()
  }

  func beginSelfManaged(isVideo: Bool) {
    prepareForCall(isVideo: isVideo)
    guard !isActive else { return }
    let rtc = RTCAudioSession.sharedInstance()
    rtc.lockForConfiguration()
    defer { rtc.unlockForConfiguration() }
    do {
      try rtc.setActive(true)
      selfManaged = true
      activated()
    } catch let error where Self.isSessionError(error, .insufficientPriority) {
      Self.log.notice("call audio self-managed activation: another call has priority")
    } catch {
      CaughtErrors.record("call audio self-managed activation", error)
    }
  }

  func callsEnded() {
    wantedRoute = nil
    videoCall = false
    reported = nil
    ringback.setWanted(false)
    inCall = false
    if AVAudioApplication.shared.isInputMuted {
      CaughtErrors.attempt("call audio unmute") {
        try AVAudioApplication.shared.setInputMuted(false)
      }
    }
    if selfManaged {
      endSelfManaged()
    } else if isActive {
      scheduleRebalance()
    } else {
      restoreIfIdle()
    }
  }

  func setRoute(_ route: CallAudioRoute) {
    wantedRoute = route
    if isActive {
      apply(route)
    }
  }

  func currentState() -> CallAudioState {
    let session = AVAudioSession.sharedInstance()
    return CallAudioRouting.state(
      outputs: session.currentRoute.outputs.map(\.portType),
      inputs: (session.availableInputs ?? []).map(\.portType))
  }

  func releaseMedia() {
    gate.setAvailable(false)
    gate.attach(nil)
    ringback.setWanted(false)
    let plugin = webRTC ?? FlutterWebRTCPlugin.sharedSingleton()
    if let connections = plugin?.peerConnections {
      for case let connection as RTCPeerConnection in connections.allValues {
        connection.close()
      }
    }
    plugin?.videoCapturer?.stopCapture()
  }

  private func activated() {
    isActive = true
    RTCAudioSession.sharedInstance().isAudioEnabled = true
    gate.setAvailable(true)
    applyStartingRoute()
    ringback.setSessionActive(true)
    report()
  }

  private func applyStartingRoute() {
    let route = CallAudioRouting.startingRoute(
      wanted: wantedRoute, isVideo: videoCall, headsets: currentState().headsets)
    if let route {
      apply(route)
    }
  }

  private func restoreRoute() {
    let route = CallAudioRouting.restoredRoute(
      reported: reported?.route, wanted: wantedRoute, isVideo: videoCall,
      headsets: currentState().headsets)
    if let route {
      apply(route)
    }
  }

  private func deactivated() {
    isActive = false
    ringback.setSessionActive(false)
    gate.setAvailable(false)
    RTCAudioSession.sharedInstance().isAudioEnabled = false
  }

  private func endSelfManaged() {
    selfManaged = false
    deactivated()
    let rtc = RTCAudioSession.sharedInstance()
    rtc.lockForConfiguration()
    CaughtErrors.attempt("call audio self-managed deactivation") { try rtc.setActive(false) }
    rtc.unlockForConfiguration()
    restoreIfIdle()
  }

  private func scheduleRebalance() {
    rebalance?.cancel()
    rebalance = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard let self, !Task.isCancelled, !self.inCall, self.isActive else { return }
      Self.log.notice("no deactivation after the last call; rebalancing")
      self.didDeactivate(.sharedInstance())
    }
  }

  @discardableResult
  private func configure() -> Bool {
    let rtc = RTCAudioSession.sharedInstance()
    let configured = CallAudioRouting.isCallConfiguration(
      category: AVAudioSession.Category(rawValue: rtc.category),
      mode: AVAudioSession.Mode(rawValue: rtc.mode), options: rtc.categoryOptions)
    guard !configured else { return false }
    rtc.lockForConfiguration()
    defer { rtc.unlockForConfiguration() }
    do {
      try rtc.setCategory(.playAndRecord, mode: .voiceChat, options: CallAudioRouting.callOptions)
      return true
    } catch {
      CaughtErrors.record("call audio configure", error)
      return false
    }
  }

  private func restoreIfIdle() {
    guard !inCall, !isActive, let saved else { return }
    self.saved = nil
    let session = AVAudioSession.sharedInstance()
    CaughtErrors.attempt("call audio restore output") { try session.overrideOutputAudioPort(.none) }
    CaughtErrors.attempt("call audio restore input") { try session.setPreferredInput(nil) }
    let rtc = RTCAudioSession.sharedInstance()
    rtc.lockForConfiguration()
    defer { rtc.unlockForConfiguration() }
    CaughtErrors.attempt("call audio restore category") {
      try rtc.setCategory(saved.category, mode: saved.mode, options: saved.options)
    }
  }

  private func apply(_ route: CallAudioRoute) {
    let session = AVAudioSession.sharedInstance()
    let inputs = session.availableInputs ?? []
    do {
      try session.overrideOutputAudioPort(route == .speaker ? .speaker : .none)
      switch CallAudioRouting.preferredInput(for: route, available: inputs.map(\.portType)) {
      case .unchanged:
        break
      case .clear:
        try session.setPreferredInput(nil)
      case .prefer(let port):
        try session.setPreferredInput(inputs.first { $0.portType == port })
      }
    } catch {
      CaughtErrors.record("call audio route \(route.rawValue)", error)
    }
  }

  private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
    if inCall, reason == .categoryChange, configure(), isActive {
      restoreRoute()
    }
    report()
  }

  private func report() {
    guard inCall, isActive else { return }
    let state = currentState()
    guard state != reported else { return }
    reported = state
    onRouteChange?(state)
  }

  private func mediaServicesWereReset() {
    Self.log.notice("media services were reset")
    guard inCall else { return }
    let reconfigured = configure()
    onMediaServicesReset?()
    guard isActive else { return }
    gate.setAvailable(false)
    gate.setAvailable(true)
    if reconfigured {
      restoreRoute()
    }
    ringback.restart()
  }
}
