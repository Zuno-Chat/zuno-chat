@preconcurrency import Flutter
import UIKit
import UniformTypeIdentifiers
@preconcurrency import WebRTC
@preconcurrency import flutter_webrtc

@MainActor
final class CallsChannelPlugin: NSObject, @preconcurrency FlutterPlugin {
  private static let clipboardLifetime: TimeInterval = 90

  private var copiedChangeCount: Int?
  private var hidesContent = false
  private var inactive = Set<ObjectIdentifier>()
  private var covers: [ObjectIdentifier: (window: UIWindow, notice: UILabel)] = [:]
  private let proximity = ProximityScreen()
  private let pictureInPicture: CallPictureInPicture
  private var calls: CallKitCenter { CallKitCenter.shared }

  private init(registrar: FlutterPluginRegistrar) {
    pictureInPicture = CallPictureInPicture { [weak registrar] in registrar?.viewController?.view }
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/calls", binaryMessenger: registrar.messenger())
    let plugin = CallsChannelPlugin(registrar: registrar)
    plugin.pictureInPicture.onCameraLive = { [weak channel] live in
      channel?.invokeMethod("pictureInPictureCameraChanged", arguments: live)
    }
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
    plugin.observeScenes()
    CallKitCenter.shared.attach(channel)
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    proximity.release()
    pictureInPicture.end()
    calls.detach()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    if handleCallKit(call.method, args, result) {
      return
    }
    switch call.method {
    case "copySensitive":
      guard let text = args?["text"] as? String else {
        result(FlutterError(code: "bad_args", message: "text is required", details: nil))
        return
      }
      let pasteboard = UIPasteboard.general
      pasteboard.setItems(
        [[UTType.utf8PlainText.identifier: text]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(Self.clipboardLifetime),
        ])
      copiedChangeCount = pasteboard.changeCount
      result(nil)
    case "clearClipboardIfMatches":
      if copiedChangeCount == UIPasteboard.general.changeCount {
        UIPasteboard.general.items = []
      }
      copiedChangeCount = nil
      result(nil)
    case "setPreventScreenshots":
      hidesContent = args?["enabled"] as? Bool == true
      updateAllScenes()
      result(nil)
    case "setProximityScreenOff":
      proximity.set(args?["enabled"] as? Bool == true)
      result(nil)
    case "setPictureInPicture":
      pictureInPicture.update(PictureInPictureRequest(arguments: args))
      result(nil)
    case "openNotificationSettings":
      openNotificationSettings()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openNotificationSettings() {
    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }

  private func handleCallKit(
    _ method: String, _ args: [String: Any]?, _ result: @escaping FlutterResult
  ) -> Bool {
    let roomId = args?["roomId"] as? String
    let callId = args?["callId"] as? String
    let uuid = (args?["uuid"] as? String).flatMap(UUID.init(uuidString:))
    switch method {
    case "takeCallEvents":
      result(calls.takeEvents())
    case "resetSystemCalls":
      proximity.set(false)
      pictureInPicture.end()
      calls.resetForNewDart()
      result(nil)
    case "armCallAudio":
      calls.audio.armEngine()
      result(nil)
    case "attachPlaceholderVideo":
      result((args?["streamId"] as? String).flatMap(PlaceholderVideo.attach(streamId:)))
    case "releasePlaceholderVideo":
      if let trackId = args?["trackId"] as? String {
        PlaceholderVideo.release(trackId: trackId)
      }
      result(nil)
    case "audioRoute":
      var state = calls.audio.currentState().arguments
      if !calls.audio.isActive {
        state.removeValue(forKey: "route")
      }
      result(state)
    case "setAudioRoute":
      if let route = (args?["route"] as? String).flatMap(CallAudioRoute.init(rawValue:)) {
        calls.audio.setRoute(route)
      }
      result(nil)
    case "startRingbackTone":
      calls.audio.ringback.setWanted(true)
      result(nil)
    case "stopRingbackTone":
      calls.audio.ringback.setWanted(false)
      result(nil)
    case "reportIncomingCall":
      guard let roomId, let callId else { return badArguments(result) }
      calls.reportIncoming(
        roomId: roomId, callId: callId, callerId: args?["callerId"] as? String ?? "",
        name: args?["name"] as? String ?? "", isVideo: args?["isVideo"] as? Bool == true
      ) { outcome in
        result(outcome)
      }
    case "updateIncoming":
      guard let roomId, let callId else { return badArguments(result) }
      calls.updateIncoming(
        roomId: roomId, callId: callId, name: args?["name"] as? String ?? "",
        isVideo: args?["video"] as? Bool == true)
      result(nil)
    case "bindIncoming":
      guard let roomId, !roomId.isEmpty, let callId, !callId.isEmpty else {
        return badArguments(result)
      }
      guard let uuid else { return badArguments(result, "uuid is required") }
      result(
        calls.bind(
          uuid: uuid, roomId: roomId, callId: callId,
          callerId: args?["callerId"] as? String ?? "", name: args?["name"] as? String ?? "",
          isVideo: args?["video"] as? Bool == true))
    case "endUnbound":
      guard let uuid else { return badArguments(result, "uuid is required") }
      calls.endUnbound(uuid: uuid)
      result(nil)
    case "declineSent":
      guard let roomId, let callId else { return badArguments(result) }
      calls.declineSent(roomId: roomId, callId: callId)
      result(nil)
    case "endIncomingCall":
      guard let roomId, let callId else { return badArguments(result) }
      calls.endIncoming(
        roomId: roomId, callId: callId,
        reason: CallIdentity.endedReason(args?["reason"] as? String))
      result(nil)
    case "startSystemCall":
      guard let roomId, let callId else { return badArguments(result) }
      result(
        calls.begin(
          roomId: roomId, callId: callId, title: args?["title"] as? String ?? "",
          isVideo: args?["isVideo"] as? Bool == true))
    case "reportCallConnected":
      guard let roomId, let callId else { return badArguments(result) }
      calls.connected(roomId: roomId, callId: callId)
      result(nil)
    case "setCallMuted":
      guard let roomId, let callId else { return badArguments(result) }
      calls.setMuted(roomId: roomId, callId: callId, muted: args?["muted"] as? Bool == true)
      result(nil)
    case "upgradeCallToVideo":
      guard let roomId, let callId else { return badArguments(result) }
      calls.upgradeToVideo(roomId: roomId, callId: callId)
      result(nil)
    case "endSystemCall":
      guard let roomId, let callId else { return badArguments(result) }
      calls.end(
        roomId: roomId, callId: callId,
        reason: CallIdentity.endedReason(args?["reason"] as? String),
        byUser: args?["byUser"] as? Bool == true)
      result(nil)
    default:
      return false
    }
    return true
  }

  private func badArguments(
    _ result: FlutterResult, _ message: String = "roomId and callId are required"
  ) -> Bool {
    result(FlutterError(code: "bad_args", message: message, details: nil))
    return true
  }

  private func observeScenes() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidDisconnect(_:)),
      name: UIScene.didDisconnectNotification, object: nil)
    center.addObserver(
      self, selector: #selector(captureDidChange(_:)),
      name: UIScreen.capturedDidChangeNotification, object: nil)
  }

  @objc private func sceneWillDeactivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    inactive.insert(ObjectIdentifier(scene))
    update(scene)
  }

  @objc private func sceneDidActivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    inactive.remove(ObjectIdentifier(scene))
    update(scene)
  }

  @objc private func sceneDidDisconnect(_ notification: Notification) {
    guard let scene = notification.object as? UIScene else { return }
    inactive.remove(ObjectIdentifier(scene))
    covers.removeValue(forKey: ObjectIdentifier(scene))?.window.isHidden = true
  }

  @objc private func captureDidChange(_ notification: Notification) {
    updateAllScenes()
  }

  private func updateAllScenes() {
    var captured = false
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      update(scene)
      captured = captured || scene.screen.isCaptured
    }
    pictureInPicture.setConcealed(hidesContent && captured)
  }

  private func update(_ scene: UIWindowScene) {
    let key = ObjectIdentifier(scene)
    let captured = scene.screen.isCaptured
    guard hidesContent, inactive.contains(key) || captured else {
      covers[key]?.window.isHidden = true
      return
    }
    let cover = covers[key] ?? makeCover(for: scene)
    covers[key] = cover
    cover.notice.isHidden = !captured
    cover.window.isHidden = false
  }

  private func makeCover(for scene: UIWindowScene) -> (window: UIWindow, notice: UILabel) {
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    let root =
      UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
      ?? UIViewController()
    let notice = UILabel()
    notice.text = "Zuno is hidden while the screen is recorded or shared."
    notice.textColor = UIColor(red: 14 / 255, green: 17 / 255, blue: 22 / 255, alpha: 1)
    notice.font = .preferredFont(forTextStyle: .body)
    notice.adjustsFontForContentSizeCategory = true
    notice.numberOfLines = 0
    notice.textAlignment = .center
    notice.translatesAutoresizingMaskIntoConstraints = false
    root.view.addSubview(notice)
    let guide = root.view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      notice.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 32),
      notice.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -32),
      notice.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -48),
    ])
    window.rootViewController = root
    return (window, notice)
  }
}

@MainActor
final class ProximityScreen {
  private var wanted = false
  private var observer: NSObjectProtocol?

  func set(_ enabled: Bool) {
    wanted = enabled
    let device = UIDevice.current
    if enabled {
      stopWaiting()
      device.isProximityMonitoringEnabled = true
    } else if device.isProximityMonitoringEnabled, device.proximityState {
      waitForProximityToClear()
    } else {
      turnOff()
    }
  }

  func release() {
    wanted = false
    turnOff()
  }

  private func turnOff() {
    stopWaiting()
    UIDevice.current.isProximityMonitoringEnabled = false
  }

  private func waitForProximityToClear() {
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.proximityChanged() }
    }
  }

  private func stopWaiting() {
    guard let observer else { return }
    NotificationCenter.default.removeObserver(observer)
    self.observer = nil
  }

  private func proximityChanged() {
    guard !wanted, !UIDevice.current.proximityState else { return }
    turnOff()
  }
}

@MainActor
private final class PlaceholderVideo {
  private static let width = 160
  private static let height = 120
  private static var active: [String: PlaceholderVideo] = [:]

  private let source: RTCVideoSource
  private let capturer: RTCVideoCapturer
  private let frame: RTCCVPixelBuffer
  private var timer: Timer?

  static func attach(streamId: String) -> String? {
    guard let plugin = FlutterWebRTCPlugin.sharedSingleton(),
      let factory = plugin.peerConnectionFactory,
      let stream = plugin.localStreams?[streamId] as? RTCMediaStream,
      let frame = blackFrame()
    else { return nil }
    let source = factory.videoSource()
    let track = factory.videoTrack(with: source, trackId: UUID().uuidString)
    plugin.localTracks?.setObject(LocalVideoTrack(track: track), forKey: track.trackId as NSString)
    stream.addVideoTrack(track)
    let placeholder = PlaceholderVideo(source: source, frame: frame)
    active[track.trackId] = placeholder
    placeholder.start()
    return track.trackId
  }

  static func release(trackId: String) {
    active.removeValue(forKey: trackId)?.stop()
  }

  private init(source: RTCVideoSource, frame: RTCCVPixelBuffer) {
    self.source = source
    self.frame = frame
    capturer = RTCVideoCapturer(delegate: source)
  }

  private func start() {
    deliver()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.deliver() }
    }
  }

  private func deliver() {
    let videoFrame = RTCVideoFrame(
      buffer: frame, rotation: ._0, timeStampNs: Int64(DispatchTime.now().uptimeNanoseconds))
    source.capturer(capturer, didCapture: videoFrame)
  }

  private func stop() {
    timer?.invalidate()
    timer = nil
  }

  private static func blackFrame() -> RTCCVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attributes =
      [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        attributes, &pixelBuffer) == kCVReturnSuccess,
      let pixelBuffer
    else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    for (plane, value) in [(0, Int32(0)), (1, Int32(128))] {
      guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else { return nil }
      memset(
        base, value,
        CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
          * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane))
    }
    return RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
  }
}
