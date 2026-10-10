import AVKit
import CoreMedia
import UIKit
@preconcurrency import WebRTC
@preconcurrency import flutter_webrtc
import os

struct PictureInPictureVideoSource: Equatable, Sendable {
  let streamId: String
  let ownerTag: String?
}

struct PictureInPictureRequest: Equatable, Sendable {
  static let off = PictureInPictureRequest(eligible: false, source: nil)

  let eligible: Bool
  let source: PictureInPictureVideoSource?

  var wantedSource: PictureInPictureVideoSource? { eligible ? source : nil }
}

extension PictureInPictureRequest {
  init(arguments: [String: Any]?) {
    let streamId = arguments?["streamId"] as? String ?? ""
    self.init(
      eligible: arguments?["eligible"] as? Bool == true,
      source: streamId.isEmpty
        ? nil
        : PictureInPictureVideoSource(
          streamId: streamId, ownerTag: arguments?["ownerTag"] as? String))
  }
}

enum PictureInPicturePlan: Equatable, Sendable {
  case show
  case hold
  case close

  static func next(eligible: Bool, supported: Bool, videoFound: Bool) -> Self {
    guard eligible, supported else { return .close }
    return videoFound ? .show : .hold
  }
}

struct PictureInPictureShape: Equatable, Sendable {
  static let longSide: CGFloat = 640
  static let portrait = CGSize(width: 3, height: 4)

  let width: Int
  let height: Int
  let degrees: Int

  init(width: Int, height: Int, degrees: Int) {
    self.width = width
    self.height = height
    self.degrees = [90, 180, 270].contains(degrees) ? degrees : 0
  }

  var isTurned: Bool { degrees == 90 || degrees == 270 }

  var angle: CGFloat { CGFloat(degrees) * .pi / 180 }

  var displaySize: CGSize {
    isTurned
      ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  func layerBounds(in size: CGSize) -> CGRect {
    CGRect(
      origin: .zero,
      size: isTurned ? CGSize(width: size.height, height: size.width) : size)
  }

  static func preferredContentSize(for size: CGSize) -> CGSize {
    guard size.width > 0, size.height > 0 else {
      return preferredContentSize(for: portrait)
    }
    let scale = longSide / max(size.width, size.height)
    return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
  }
}

struct PictureInPictureFrameGate: Sendable {
  static let warmInterval: UInt64 = 500_000_000

  var live = false
  private var lastWarm: UInt64?

  mutating func admits(at now: UInt64) -> Bool {
    if live { return true }
    if let lastWarm, now < lastWarm + Self.warmInterval { return false }
    lastWarm = now
    return true
  }
}

enum PictureInPictureSamples {
  static func make(_ pixelBuffer: CVPixelBuffer, reusing format: CMVideoFormatDescription?)
    -> (sample: CMSampleBuffer, format: CMVideoFormatDescription)?
  {
    var format = format
    if let current = format,
      !CMVideoFormatDescriptionMatchesImageBuffer(current, imageBuffer: pixelBuffer)
    {
      format = nil
    }
    if format == nil {
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
    }
    guard let format else { return nil }
    var timing = CMSampleTimingInfo(
      duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format,
        sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
      let sample
    else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
      CFArrayGetCount(attachments) > 0
    {
      let attachment = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    return (sample, format)
  }
}

final class PictureInPictureFeed: NSObject, RTCVideoRenderer, @unchecked Sendable {
  typealias ShapeHandler =
    @MainActor @Sendable (PictureInPictureFeed, PictureInPictureShape) -> Void

  private static let maxQueuedFrames = 2

  private let renderer: AVSampleBufferVideoRenderer
  private let onShape: ShapeHandler
  private let queue = DispatchQueue(label: "im.zuno.calls.pip-video", qos: .userInteractive)
  private let lock = NSLock()
  private var gate = PictureInPictureFrameGate()
  private var accepting = false
  private var queued = 0
  private var shape: PictureInPictureShape?
  private var format: CMVideoFormatDescription?
  private var pool: CVPixelBufferPool?
  private var poolWidth: Int32 = 0
  private var poolHeight: Int32 = 0

  init(renderer: AVSampleBufferVideoRenderer, onShape: @escaping ShapeHandler) {
    self.renderer = renderer
    self.onShape = onShape
  }

  func setLive(_ live: Bool) {
    lock.withLock { gate.live = live }
  }

  func start() {
    lock.withLock { accepting = true }
  }

  func stop() {
    lock.withLock { accepting = false }
    queue.async { [self] in
      shape = nil
      renderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }
  }

  func setSize(_ size: CGSize) {}

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    let admitted = lock.withLock {
      guard accepting, queued < Self.maxQueuedFrames, gate.admits(at: now) else { return false }
      queued += 1
      return true
    }
    guard admitted else { return }
    let box = UncheckedSendable(frame)
    queue.async { [weak self] in self?.present(box.value) }
  }

  private func present(_ frame: RTCVideoFrame) {
    defer { lock.withLock { queued -= 1 } }
    let next = PictureInPictureShape(
      width: Int(frame.width), height: Int(frame.height), degrees: frame.rotation.rawValue)
    if next != shape {
      shape = next
      let onShape = onShape
      DispatchQueue.main.async { [self] in
        MainActor.assumeIsolated { onShape(self, next) }
      }
    }
    guard let pixelBuffer = pixelBuffer(for: frame.buffer),
      let made = PictureInPictureSamples.make(pixelBuffer, reusing: format)
    else { return }
    format = made.format
    if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
      renderer.flush()
    }
    renderer.enqueue(made.sample)
  }

  private func pixelBuffer(for buffer: any RTCVideoFrameBuffer) -> CVPixelBuffer? {
    if let native = buffer as? RTCCVPixelBuffer, !native.requiresCropping() {
      return native.pixelBuffer
    }
    let i420 = buffer.toI420()
    guard let output = poolBuffer(width: i420.width, height: i420.height) else { return nil }
    CVPixelBufferLockBaseAddress(output, [])
    defer { CVPixelBufferUnlockBaseAddress(output, []) }
    guard let y = CVPixelBufferGetBaseAddressOfPlane(output, 0),
      let uv = CVPixelBufferGetBaseAddressOfPlane(output, 1)
    else { return nil }
    RTCYUVHelper.i420(
      toNV12: i420.dataY, srcStrideY: i420.strideY, srcU: i420.dataU, srcStrideU: i420.strideU,
      srcV: i420.dataV, srcStrideV: i420.strideV, dstY: y.assumingMemoryBound(to: UInt8.self),
      dstStrideY: Int32(CVPixelBufferGetBytesPerRowOfPlane(output, 0)),
      dstUV: uv.assumingMemoryBound(to: UInt8.self),
      dstStrideUV: Int32(CVPixelBufferGetBytesPerRowOfPlane(output, 1)), width: i420.width,
      height: i420.height)
    return output
  }

  private func poolBuffer(width: Int32, height: Int32) -> CVPixelBuffer? {
    if pool == nil || poolWidth != width || poolHeight != height {
      pool = nil
      poolWidth = width
      poolHeight = height
      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ]
      CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    }
    guard let pool else { return nil }
    var output: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
    return output
  }
}

final class PictureInPictureVideoView: UIView {
  let displayLayer = AVSampleBufferDisplayLayer()

  var shape: PictureInPictureShape? {
    didSet {
      if shape != oldValue { setNeedsLayout() }
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    isUserInteractionEnabled = false
    displayLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(displayLayer)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let shape = shape ?? PictureInPictureShape(width: 0, height: 0, degrees: 0)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    displayLayer.bounds = shape.layerBounds(in: bounds.size)
    displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: shape.angle))
    CATransaction.commit()
  }
}

@MainActor
private final class VideoCallWindow {
  let controller: AVPictureInPictureController
  let content: AVPictureInPictureVideoCallViewController
  let view: PictureInPictureVideoView
  let feed: PictureInPictureFeed
  private(set) var track: RTCVideoTrack?

  init(sourceView: UIView, onShape: @escaping PictureInPictureFeed.ShapeHandler) {
    let content = AVPictureInPictureVideoCallViewController()
    let view = PictureInPictureVideoView(frame: content.view.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    content.view.backgroundColor = .black
    content.view.addSubview(view)
    self.content = content
    self.view = view
    feed = PictureInPictureFeed(renderer: view.displayLayer.sampleBufferRenderer, onShape: onShape)
    controller = AVPictureInPictureController(
      contentSource: AVPictureInPictureController.ContentSource(
        activeVideoCallSourceView: sourceView, contentViewController: content))
  }

  var sourceView: UIView? { controller.contentSource?.activeVideoCallSourceView }

  func show(_ next: RTCVideoTrack) {
    guard next !== track else { return }
    if let track {
      track.remove(feed)
      feed.stop()
    }
    track = next
    feed.start()
    next.add(feed)
  }

  func hold() {
    track?.remove(feed)
    track = nil
  }

  func close() {
    track?.remove(feed)
    track = nil
    feed.stop()
    controller.delegate = nil
    controller.contentSource = nil
  }
}

@MainActor
final class CallCameraWatch {
  private(set) var interrupted = false
  var onChange: (() -> Void)?
  private var capturer: NSKeyValueObservation?
  private weak var session: AVCaptureSession?
  private var observers: [NSObjectProtocol] = []

  func start() {
    guard capturer == nil, let plugin = FlutterWebRTCPlugin.sharedSingleton() else { return }
    capturer = plugin.observe(\.videoCapturer, options: [.initial, .new]) {
      [weak self] _, change in
      let session = UncheckedSendable(change.newValue??.captureSession)
      if Thread.isMainThread {
        MainActor.assumeIsolated { self?.watch(session.value) }
      } else {
        DispatchQueue.main.async {
          MainActor.assumeIsolated { self?.watch(session.value) }
        }
      }
    }
  }

  private func watch(_ next: AVCaptureSession?) {
    guard next !== session else { return }
    let center = NotificationCenter.default
    observers.forEach(center.removeObserver)
    observers = []
    session = next
    if let next {
      if next.isMultitaskingCameraAccessSupported, !next.isMultitaskingCameraAccessEnabled,
        !next.isRunning
      {
        next.isMultitaskingCameraAccessEnabled = true
      }
      observers = [
        center.addObserver(
          forName: AVCaptureSession.wasInterruptedNotification, object: next, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.setInterrupted(true) }
        },
        center.addObserver(
          forName: AVCaptureSession.interruptionEndedNotification, object: next, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.setInterrupted(false) }
        },
      ]
    }
    setInterrupted(next?.isInterrupted ?? false)
  }

  private func setInterrupted(_ value: Bool) {
    guard value != interrupted else { return }
    interrupted = value
    onChange?()
  }
}

@MainActor
final class CallPictureInPicture: NSObject {
  nonisolated static let log = Logger(subsystem: "im.zuno.chat", category: "pip")

  var onCameraLive: ((Bool) -> Void)?
  private let sourceView: @MainActor () -> UIView?
  private let camera = CallCameraWatch()
  private var request = PictureInPictureRequest.off
  private var concealed = false
  private var showing = false {
    didSet { updateCameraLive() }
  }
  private var cameraLive = false
  private var window: VideoCallWindow?
  private var activeObserver: NSObjectProtocol?

  init(sourceView: @escaping @MainActor () -> UIView?) {
    self.sourceView = sourceView
    super.init()
    camera.onChange = { [weak self] in self?.updateCameraLive() }
    camera.start()
    activeObserver = NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.activated() }
    }
  }

  func update(_ next: PictureInPictureRequest) {
    request = next
    reconcile()
  }

  func setConcealed(_ value: Bool) {
    concealed = value
    window?.view.isHidden = value
  }

  func end() {
    request = .off
    closeWindow()
  }

  private func activated() {
    if showing {
      window?.controller.stopPictureInPicture()
    } else {
      reconcile()
    }
  }

  private func reconcile() {
    let track = request.wantedSource.flatMap(Self.videoTrack(for:))
    let plan = PictureInPicturePlan.next(
      eligible: request.eligible,
      supported: AVPictureInPictureController.isPictureInPictureSupported(),
      videoFound: track != nil)
    switch plan {
    case .close:
      closeWindow()
    case .hold:
      window?.hold()
    case .show:
      guard let track else { return }
      if !showing, let current = window, current.sourceView !== sourceView() {
        closeWindow()
      }
      guard let window = window ?? open() else { return }
      window.show(track)
      window.controller.canStartPictureInPictureAutomaticallyFromInline = true
    }
  }

  private func open() -> VideoCallWindow? {
    guard let sourceView = sourceView() else { return nil }
    let opened = VideoCallWindow(sourceView: sourceView) { [weak self] feed, shape in
      self?.shapeChanged(feed, shape)
    }
    opened.controller.delegate = self
    opened.content.preferredContentSize = PictureInPictureShape.preferredContentSize(for: .zero)
    opened.view.isHidden = concealed
    window = opened
    return opened
  }

  private func closeWindow() {
    guard let closing = window else { return }
    if showing {
      Self.log.notice("picture-in-picture closed by the call")
    }
    window = nil
    closing.controller.canStartPictureInPictureAutomaticallyFromInline = false
    closing.close()
    showing = false
  }

  private func shapeChanged(_ feed: PictureInPictureFeed, _ shape: PictureInPictureShape) {
    guard let window, window.feed === feed else { return }
    window.view.shape = shape
    let size = PictureInPictureShape.preferredContentSize(for: shape.displaySize)
    if window.content.preferredContentSize != size {
      window.content.preferredContentSize = size
    }
  }

  private func updateCameraLive() {
    let live = showing && !camera.interrupted
    guard live != cameraLive else { return }
    cameraLive = live
    Self.log.notice("camera kept in picture-in-picture: \(live, privacy: .public)")
    onCameraLive?(live)
  }

  private func stopped() {
    showing = false
    window?.feed.setLive(false)
    reconcile()
  }

  private static func videoTrack(for source: PictureInPictureVideoSource) -> RTCVideoTrack? {
    guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else { return nil }
    let local =
      source.ownerTag == "local"
      ? plugin.localStreams?[source.streamId] as? RTCMediaStream : nil
    let stream = local ?? plugin.stream(forId: source.streamId, peerConnectionId: source.ownerTag)
    return stream?.videoTracks.first
  }
}

extension CallPictureInPicture: @preconcurrency AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    Self.log.notice("picture-in-picture starting")
    showing = true
    window?.feed.setLive(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: any Error
  ) {
    CaughtErrors.record("call pip start", error)
    stopped()
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    Self.log.notice("picture-in-picture stopped")
    stopped()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}
