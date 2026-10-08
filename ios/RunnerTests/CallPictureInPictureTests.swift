import CoreMedia
import CoreVideo
import XCTest

@testable import Runner

final class PictureInPictureRequestTests: XCTestCase {
  func testReadsTheVideoToShow() {
    let request = PictureInPictureRequest(arguments: [
      "eligible": true, "aspectWidth": 640, "aspectHeight": 480, "streamId": "ann-video",
      "ownerTag": "local",
    ])

    XCTAssertEqual(
      request.wantedSource, PictureInPictureVideoSource(streamId: "ann-video", ownerTag: "local"))
  }

  func testAnIneligibleCallWantsNoVideo() {
    let request = PictureInPictureRequest(arguments: [
      "eligible": false, "aspectWidth": 640, "aspectHeight": 480, "streamId": "ann-video",
    ])

    XCTAssertNil(request.wantedSource)
  }

  func testAnEligibleCallWithoutAStreamWantsNoVideo() {
    XCTAssertNil(PictureInPictureRequest(arguments: ["eligible": true]).wantedSource)
    XCTAssertNil(
      PictureInPictureRequest(arguments: ["eligible": true, "streamId": ""]).wantedSource)
  }

  func testMissingOrMalformedArgumentsMeanOff() {
    XCTAssertEqual(PictureInPictureRequest(arguments: nil), .off)
    XCTAssertEqual(
      PictureInPictureRequest(arguments: ["eligible": "yes", "aspectWidth": 0]), .off)
  }
}

final class PictureInPicturePlanTests: XCTestCase {
  func testAnEligibleCallWithItsVideoIsShown() {
    XCTAssertEqual(PictureInPicturePlan.next(eligible: true, supported: true, videoFound: true), .show)
  }

  func testAVideoMissingForAMomentKeepsTheWindow() {
    XCTAssertEqual(
      PictureInPicturePlan.next(eligible: true, supported: true, videoFound: false), .hold)
  }

  func testAnIneligibleCallClosesTheWindow() {
    XCTAssertEqual(
      PictureInPicturePlan.next(eligible: false, supported: true, videoFound: true), .close)
    XCTAssertEqual(
      PictureInPicturePlan.next(eligible: false, supported: true, videoFound: false), .close)
  }

  func testADeviceWithoutPictureInPictureNeverOpensOne() {
    XCTAssertEqual(
      PictureInPicturePlan.next(eligible: true, supported: false, videoFound: true), .close)
  }
}

final class PictureInPictureShapeTests: XCTestCase {
  func testAQuarterTurnSwapsTheDisplayedSides() {
    let shape = PictureInPictureShape(width: 640, height: 480, degrees: 90)

    XCTAssertEqual(shape.displaySize, CGSize(width: 480, height: 640))
    XCTAssertEqual(
      shape.layerBounds(in: CGSize(width: 90, height: 160)),
      CGRect(x: 0, y: 0, width: 160, height: 90))
    XCTAssertEqual(shape.angle, .pi / 2, accuracy: 0.0001)
  }

  func testAHalfTurnKeepsTheSides() {
    let shape = PictureInPictureShape(width: 640, height: 480, degrees: 180)

    XCTAssertEqual(shape.displaySize, CGSize(width: 640, height: 480))
    XCTAssertEqual(
      shape.layerBounds(in: CGSize(width: 160, height: 90)),
      CGRect(x: 0, y: 0, width: 160, height: 90))
  }

  func testAnUnknownRotationReadsAsUpright() {
    XCTAssertEqual(PictureInPictureShape(width: 4, height: 3, degrees: 45).degrees, 0)
  }

  func testTheWindowSizeFollowsTheShapeNotTheResolution() {
    XCTAssertEqual(
      PictureInPictureShape.preferredContentSize(for: CGSize(width: 480, height: 640)),
      CGSize(width: 480, height: 640))
    XCTAssertEqual(
      PictureInPictureShape.preferredContentSize(for: CGSize(width: 180, height: 240)),
      CGSize(width: 480, height: 640))
    XCTAssertEqual(
      PictureInPictureShape.preferredContentSize(for: CGSize(width: 1280, height: 720)),
      CGSize(width: 640, height: 360))
  }

  func testNoSizeYetFallsBackToPortrait() {
    XCTAssertEqual(
      PictureInPictureShape.preferredContentSize(for: .zero), CGSize(width: 480, height: 640))
  }
}

final class PictureInPictureFrameGateTests: XCTestCase {
  private let second: UInt64 = 1_000_000_000

  func testBeforeTheWindowOpensOnlyTwoFramesASecondPass() {
    var gate = PictureInPictureFrameGate()

    XCTAssertTrue(gate.admits(at: 10 * second))
    XCTAssertFalse(gate.admits(at: 10 * second + 100_000_000))
    XCTAssertFalse(gate.admits(at: 10 * second + 499_999_999))
    XCTAssertTrue(gate.admits(at: 10 * second + 500_000_000))
  }

  func testAnOpenWindowTakesEveryFrame() {
    var gate = PictureInPictureFrameGate()
    gate.live = true

    XCTAssertTrue(gate.admits(at: second))
    XCTAssertTrue(gate.admits(at: second + 1))
    XCTAssertTrue(gate.admits(at: second + 2))
  }

  func testClosingTheWindowThrottlesAgain() {
    var gate = PictureInPictureFrameGate()
    gate.live = true
    _ = gate.admits(at: second)
    gate.live = false

    XCTAssertTrue(gate.admits(at: second + 1))
    XCTAssertFalse(gate.admits(at: second + 2))
  }
}

final class PictureInPictureSamplesTests: XCTestCase {
  private func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buffer)
    XCTAssertEqual(status, kCVReturnSuccess)
    return try XCTUnwrap(buffer)
  }

  func testAFrameIsShownTheMomentItArrives() throws {
    let made = try XCTUnwrap(
      PictureInPictureSamples.make(try pixelBuffer(width: 16, height: 12), reusing: nil))

    let attachments = try XCTUnwrap(
      CMSampleBufferGetSampleAttachmentsArray(made.sample, createIfNecessary: false)
        as? [[CFString: Any]])
    XCTAssertEqual(attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] as? Bool, true)
    XCTAssertEqual(
      CMVideoFormatDescriptionGetDimensions(made.format).width, 16)
  }

  func testTheFormatIsReusedUntilTheSizeChanges() throws {
    let first = try XCTUnwrap(
      PictureInPictureSamples.make(try pixelBuffer(width: 16, height: 12), reusing: nil))
    let same = try XCTUnwrap(
      PictureInPictureSamples.make(
        try pixelBuffer(width: 16, height: 12), reusing: first.format))
    let resized = try XCTUnwrap(
      PictureInPictureSamples.make(
        try pixelBuffer(width: 32, height: 24), reusing: first.format))

    XCTAssertTrue(same.format === first.format)
    XCTAssertFalse(resized.format === first.format)
    XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(resized.format).width, 32)
  }
}
