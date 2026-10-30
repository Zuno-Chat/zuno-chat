@preconcurrency import AVFoundation
import Flutter
import Foundation
import Synchronization
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
    .mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers,
  ]

  static func callOptions(speakerFirst: Bool) -> AVAudioSession.CategoryOptions {
    speakerFirst ? callOptions.union(.defaultToSpeaker) : callOptions
  }

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

  static func isCallConfiguration(
    category: AVAudioSession.Category, mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions, speakerFirst: Bool
  ) -> Bool {
    isCallConfiguration(category: category, mode: mode, options: options)
      && options.contains(.defaultToSpeaker) == speakerFirst
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

final class CallToneSource: @unchecked Sendable {
  private final class Render: @unchecked Sendable {
    let samples: UnsafeMutableBufferPointer<Float>
    let playing = Atomic<Bool>(false)
    let rewind = Atomic<Bool>(false)
    var position = 0

    init(samples: UnsafeMutableBufferPointer<Float>) {
      self.samples = samples
    }

    deinit {
      samples.deallocate()
    }
  }

  let node: AVAudioSourceNode
  let format: AVAudioFormat
  private let render: Render

  init?(contentsOf url: URL) {
    guard let file = try? AVAudioFile(forReading: url),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
      (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
      let channel = buffer.floatChannelData?[0],
      let format = AVAudioFormat(
        standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)
    else { return nil }
    let samples = UnsafeMutableBufferPointer<Float>.allocate(capacity: Int(buffer.frameLength))
    _ = samples.initialize(from: UnsafeBufferPointer(start: channel, count: samples.count))
    let render = Render(samples: samples)
    self.render = render
    self.format = format
    node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, data in
      let buffers = UnsafeMutableAudioBufferListPointer(data)
      guard render.playing.load(ordering: .acquiring) else {
        isSilence.pointee = true
        for buffer in buffers {
          if let bytes = buffer.mData { memset(bytes, 0, Int(buffer.mDataByteSize)) }
        }
        return noErr
      }
      if render.rewind.exchange(false, ordering: .relaxed) { render.position = 0 }
      let count = render.samples.count
      var position = render.position
      for buffer in buffers {
        guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        position = render.position
        for frame in 0..<Int(frameCount) {
          out[frame] = render.samples[position]
          position = position + 1 == count ? 0 : position + 1
        }
      }
      render.position = position
      return noErr
    }
  }

  func setPlaying(_ playing: Bool) {
    if playing, !render.playing.load(ordering: .relaxed) {
      render.rewind.store(true, ordering: .relaxed)
    }
    render.playing.store(playing, ordering: .releasing)
  }

  func join(_ engine: AVAudioEngine, mixer: AVAudioMixerNode) {
    if node.engine !== engine {
      node.engine?.detach(node)
      engine.attach(node)
    }
    if engine.outputConnectionPoints(for: node, outputBus: 0).isEmpty {
      engine.connect(
        node, to: mixer, fromBus: 0, toBus: mixer.nextAvailableInputBus, format: format)
    }
  }

  func leave(_ engine: AVAudioEngine) {
    if node.engine === engine {
      engine.detach(node)
    }
  }
}

final class CallToneSlot: Sendable {
  private let loaded = Mutex<CallToneSource?>(nil)

  var source: CallToneSource? { loaded.withLock { $0 } }

  func load(_ url: URL) -> CallToneSource? {
    loaded.withLock { current in
      if current == nil { current = CallToneSource(contentsOf: url) }
      return current
    }
  }
}

final class CallAudioEngineObserver: NSObject, RTCAudioDeviceModuleDelegate, @unchecked Sendable {
  private let tone: CallToneSlot
  private weak var plugin: FlutterWebRTCPlugin?

  init(plugin: FlutterWebRTCPlugin?, tone: CallToneSlot) {
    self.plugin = plugin
    self.tone = tone
  }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule,
    didReceiveSpeechActivityEvent speechActivityEvent: RTCSpeechActivityEvent
  ) {}

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, didCreateEngine engine: AVAudioEngine
  ) -> Int { 0 }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, willStartEngine engine: AVAudioEngine,
    isPlayoutEnabled: Bool, isRecordingEnabled: Bool
  ) -> Int {
    return 0
  }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, didStopEngine engine: AVAudioEngine,
    isPlayoutEnabled: Bool, isRecordingEnabled: Bool
  ) -> Int { 0 }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, didDisableEngine engine: AVAudioEngine,
    isPlayoutEnabled: Bool, isRecordingEnabled: Bool
  ) -> Int { 0 }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, willReleaseEngine engine: AVAudioEngine
  ) -> Int {
    tone.source?.leave(engine)
    return 0
  }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, engine: AVAudioEngine,
    configureInputFromSource source: AVAudioNode?, toDestination destination: AVAudioNode,
    format: AVAudioFormat, context: [AnyHashable: Any]
  ) -> Int { 0 }

  func audioDeviceModule(
    _ audioDeviceModule: RTCAudioDeviceModule, engine: AVAudioEngine,
    configureOutputFromSource source: AVAudioNode, toDestination destination: AVAudioNode?,
    format: AVAudioFormat, context: [AnyHashable: Any]
  ) -> Int {
    if let mixer = source as? AVAudioMixerNode {
      tone.source?.join(engine, mixer: mixer)
    }
    return 0
  }

  func audioDeviceModuleDidUpdateDevices(_ audioDeviceModule: RTCAudioDeviceModule) {
    plugin?.audioDeviceModuleDidUpdateDevices(audioDeviceModule)
  }
}

final class CallAudioEngineGate: @unchecked Sendable {
  private let queue = DispatchQueue(label: "im.zuno.calls.audio-gate")
  private var factory: RTCPeerConnectionFactory?
  private var module: RTCAudioDeviceModule?
  private var observer: CallAudioEngineObserver?
  private var available = false
  private var applied: Bool?
  private let tone: CallToneSlot

  init(tone: CallToneSlot) {
    self.tone = tone
  }

  func attach(_ factory: RTCPeerConnectionFactory?, plugin: FlutterWebRTCPlugin?) {
    let box = UncheckedSendable((factory, plugin))
    queue.async { [self] in
      if self.factory !== box.value.0 {
        self.factory = box.value.0
        module = box.value.0?.audioDeviceModule
        module?.duckingLevel = .min
        observer = module.map { _ in
          CallAudioEngineObserver(plugin: box.value.1, tone: tone)
        }
        module?.observer = observer
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
  let tone = CallToneSlot()

  func start(asset: String?) {
    guard let url = asset.flatMap(Self.bundledURL(forAsset:)), let source = tone.load(url) else {
      CaughtErrors.record("call ringback tone", CocoaError(.fileNoSuchFile))
      return
    }
    source.setPlaying(true)
  }

  func stop() {
    tone.source?.setPlaying(false)
  }

  nonisolated static func bundledURL(forAsset asset: String) -> URL? {
    Bundle.main.path(forResource: FlutterDartProject.lookupKey(forAsset: asset), ofType: nil)
      .map(URL.init(fileURLWithPath:))
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
  private lazy var gate = CallAudioEngineGate(tone: ringback.tone)
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
  private var speakerFirst = false
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
      gate.attach(nil, plugin: nil)
    }
  }

  func armEngine() {
    let plugin = webRTC ?? FlutterWebRTCPlugin.sharedSingleton()
    gate.attach(plugin?.peerConnectionFactory, plugin: plugin)
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
    speakerFirst =
      CallAudioRouting.startingRoute(
        wanted: wantedRoute, isVideo: videoCall, headsets: currentState().headsets) == .speaker
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
    speakerFirst = false
    videoCall = false
    reported = nil
    ringback.stop()
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
    gate.attach(nil, plugin: nil)
    ringback.stop()
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

  private var sessionInCallConfiguration: Bool {
    let rtc = RTCAudioSession.sharedInstance()
    return CallAudioRouting.isCallConfiguration(
      category: AVAudioSession.Category(rawValue: rtc.category),
      mode: AVAudioSession.Mode(rawValue: rtc.mode), options: rtc.categoryOptions)
  }

  private var sessionInWantedCallConfiguration: Bool {
    let rtc = RTCAudioSession.sharedInstance()
    return CallAudioRouting.isCallConfiguration(
      category: AVAudioSession.Category(rawValue: rtc.category),
      mode: AVAudioSession.Mode(rawValue: rtc.mode), options: rtc.categoryOptions,
      speakerFirst: speakerFirst)
  }

  @discardableResult
  private func configure() -> Bool {
    guard !sessionInWantedCallConfiguration else { return false }
    let rtc = RTCAudioSession.sharedInstance()
    rtc.lockForConfiguration()
    defer { rtc.unlockForConfiguration() }
    do {
      try rtc.setCategory(
        .playAndRecord, mode: .voiceChat,
        options: CallAudioRouting.callOptions(speakerFirst: speakerFirst))
      return true
    } catch {
      CaughtErrors.record("call audio configure", error)
      return false
    }
  }

  private func restoreIfIdle() {
    guard !inCall, !isActive, let saved else { return }
    self.saved = nil
    guard sessionInCallConfiguration else { return }
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
    speakerFirst = route == .speaker
    configure()
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
  }
}
