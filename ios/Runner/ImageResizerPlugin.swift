@preconcurrency import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ImageResizerPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let queue = DispatchQueue(label: "im.zuno.image", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zuno/image", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ImageResizerPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "resize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
      let bytes = args["bytes"] as? FlutterStandardTypedData,
      let maxDimension = args["maxDimension"] as? Int,
      let quality = args["quality"] as? Int
    else {
      result(nil)
      return
    }
    let data = bytes.data
    Task {
      let reply = await withCheckedContinuation { continuation in
        queue.async {
          continuation.resume(
            returning: autoreleasepool {
              Self.resize(data, maxDimension: maxDimension, quality: quality)
            })
        }
      }
      result(reply)
    }
  }

  private nonisolated static func resize(
    _ data: Data, maxDimension: Int, quality: Int
  ) -> [String: Any]? {
    guard maxDimension > 0,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { return nil }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxDimension),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }

    let png = CGImageSourceGetType(source) as String? == UTType.png.identifier
    let type = png ? UTType.png : UTType.jpeg
    let encoded = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        encoded, type.identifier as CFString, 1, nil)
    else { return nil }
    let encoding: [CFString: Any] =
      png
      ? [:] : [kCGImageDestinationLossyCompressionQuality: Double(min(max(quality, 0), 100)) / 100]
    CGImageDestinationAddImage(destination, image, encoding as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }

    return [
      "bytes": FlutterStandardTypedData(bytes: encoded as Data),
      "width": image.width,
      "height": image.height,
      "mimeType": png ? "image/png" : "image/jpeg",
    ]
  }
}
