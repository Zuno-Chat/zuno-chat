import AVFoundation
@preconcurrency import Flutter
import UIKit

@MainActor
final class VideoToolsPlugin: NSObject, @preconcurrency FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/video", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(VideoToolsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "probe":
      guard let path = args?["path"] as? String else {
        result(nil)
        return
      }
      Task { result(await Self.probe(path: path)) }
    case "remux":
      guard let input = args?["input"] as? String, let output = args?["output"] as? String else {
        result(false)
        return
      }
      Task { result(await Self.remux(input: input, output: output)) }
    case "thumbnail":
      guard let path = args?["path"] as? String,
        let maxDimension = args?["maxDimension"] as? Int,
        let quality = args?["quality"] as? Int
      else {
        result(nil)
        return
      }
      Task {
        result(await Self.thumbnail(path: path, maxDimension: maxDimension, quality: quality))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private nonisolated static let aacSubtypes: Set<FourCharCode> = [
    kAudioFormatMPEG4AAC,
    kAudioFormatMPEG4AAC_HE,
    kAudioFormatMPEG4AAC_HE_V2,
    kAudioFormatMPEG4AAC_LD,
    kAudioFormatMPEG4AAC_ELD,
  ]

  private nonisolated static func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
    return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
  }

  private nonisolated static func codecName(
    _ formats: [CMFormatDescription], video: Bool
  ) -> String? {
    guard let format = formats.first else { return nil }
    let subtype = CMFormatDescriptionGetMediaSubType(format)
    if video {
      switch subtype {
      case kCMVideoCodecType_H264: return "video/avc"
      case kCMVideoCodecType_HEVC: return "video/hevc"
      default: return "video/x-\(fourCC(subtype))"
      }
    }
    return aacSubtypes.contains(subtype) ? "audio/mp4a-latm" : "audio/x-\(fourCC(subtype))"
  }

  @concurrent
  private nonisolated static func probe(path: String) async -> sending [String: Any]? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    do {
      guard let video = try await asset.loadTracks(withMediaType: .video).first else { return nil }
      let (size, transform, videoFormats) = try await video.load(
        .naturalSize, .preferredTransform, .formatDescriptions)
      let shown = size.applying(transform)
      let width = Int(abs(shown.width).rounded())
      let height = Int(abs(shown.height).rounded())
      guard width > 0, height > 0 else { return nil }

      let seconds = try await asset.load(.duration).seconds
      let known = seconds.isFinite && seconds > 0
      let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
        .doubleValue
      let quarterTurns = Int((atan2(transform.b, transform.a) / (.pi / 2)).rounded())
      var reply: [String: Any] = [
        "width": width,
        "height": height,
        "rotated": quarterTurns % 2 != 0,
      ]
      if let codec = codecName(videoFormats, video: true) {
        reply["videoCodec"] = codec
      }
      if known {
        reply["durationMs"] = Int((seconds * 1000).rounded())
        if let fileSize {
          reply["bitrate"] = Int((fileSize * 8 / seconds).rounded())
        }
      }
      if let audio = try await asset.loadTracks(withMediaType: .audio).first {
        reply["audioCodec"] = codecName(try await audio.load(.formatDescriptions), video: false)
      }
      return reply
    } catch {
      return nil
    }
  }

  @concurrent
  private nonisolated static func remux(input: String, output: String) async -> Bool {
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    let composition = AVMutableComposition()
    do {
      var copied = false
      for type in [AVMediaType.video, .audio] {
        for source in try await asset.loadTracks(withMediaType: type) {
          guard
            let track = composition.addMutableTrack(
              withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
          else { return false }
          let (range, transform) = try await source.load(.timeRange, .preferredTransform)
          try track.insertTimeRange(range, of: source, at: range.start)
          if type == .video { track.preferredTransform = transform }
          copied = true
        }
      }
      guard copied,
        let session = AVAssetExportSession(
          asset: composition, presetName: AVAssetExportPresetPassthrough)
      else { return false }
      let url = URL(fileURLWithPath: output)
      try? FileManager.default.removeItem(at: url)
      session.metadata = []
      session.metadataItemFilter = .forSharing()
      try await session.export(to: url, as: .mp4)
      return true
    } catch {
      try? FileManager.default.removeItem(atPath: output)
      return false
    }
  }

  @concurrent
  private nonisolated static func thumbnail(
    path: String,
    maxDimension: Int,
    quality: Int
  ) async -> sending [String: Any]? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
    let reply: [String: Any]? = await withCheckedContinuation { continuation in
      generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) {
        _, frame, _, status, _ in
        guard status == .succeeded, let frame,
          let jpeg = UIImage(cgImage: frame).jpegData(
            compressionQuality: CGFloat(min(max(quality, 0), 100)) / 100)
        else {
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: [
          "bytes": FlutterStandardTypedData(bytes: jpeg),
          "width": frame.width,
          "height": frame.height,
          "mimeType": "image/jpeg",
        ])
      }
    }
    withExtendedLifetime(generator) {}
    return reply
  }
}
