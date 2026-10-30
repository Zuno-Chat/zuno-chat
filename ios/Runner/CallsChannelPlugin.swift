@preconcurrency import Flutter
import UIKit
@preconcurrency import WebRTC
@preconcurrency import flutter_webrtc

@MainActor
final class CallsChannelPlugin: NSObject, @preconcurrency FlutterPlugin {
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
    ScreenCover.shared.pictureInPicture = plugin.pictureInPicture
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
      calls.audio.ringback.start(asset: args?["asset"] as? String)
      result(nil)
    case "stopRingbackTone":
      calls.audio.ringback.stop()
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

enum PlaceholderVideoUnavailable: Error {
  case noWebRTCPlugin, noPeerConnectionFactory, noSuchStream, noBlackFrame
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
    guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
      return unavailable(.noWebRTCPlugin)
    }
    guard let factory = plugin.peerConnectionFactory else {
      return unavailable(.noPeerConnectionFactory)
    }
    guard let stream = plugin.localStreams?[streamId] as? RTCMediaStream else {
      return unavailable(.noSuchStream)
    }
    guard let frame = blackFrame() else { return unavailable(.noBlackFrame) }
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

  private static func unavailable(_ reason: PlaceholderVideoUnavailable) -> String? {
    CaughtErrors.record("placeholder video unavailable", reason)
    return nil
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
