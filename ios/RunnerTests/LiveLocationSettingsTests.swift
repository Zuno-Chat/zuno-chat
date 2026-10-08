import CoreLocation
import XCTest

@testable import Runner

final class LiveLocationSettingsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func location(accuracy: CLLocationAccuracy = 20, age: TimeInterval = 1) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4), altitude: 0,
      horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
  }

  func testCoarseModeAsksForAHundredMetresAndForwardsEveryFiveMinutes() {
    let settings = LiveLocationSettings.of(.coarse)

    XCTAssertEqual(settings.desiredAccuracy, kCLLocationAccuracyHundredMeters)
    XCTAssertEqual(settings.forwardInterval, 300)
  }

  func testPreciseModeAsksForTheBestFixAndForwardsEveryFiveSeconds() {
    let settings = LiveLocationSettings.of(.precise)

    XCTAssertEqual(settings.desiredAccuracy, kCLLocationAccuracyBest)
    XCTAssertEqual(settings.forwardInterval, 5)
  }

  func testTheFirstCurrentFixIsForwarded() {
    XCTAssertTrue(
      LiveLocationSettings.of(.coarse).forwards(location(), now: now, lastForwardAt: nil))
  }

  func testAFixWithoutAValidAccuracyIsDropped() {
    XCTAssertFalse(
      LiveLocationSettings.of(.precise).forwards(
        location(accuracy: -1), now: now, lastForwardAt: nil))
  }

  func testAStaleCachedFixIsDropped() {
    XCTAssertFalse(
      LiveLocationSettings.of(.coarse).forwards(location(age: 120), now: now, lastForwardAt: nil))
  }

  func testFixesWithinTheIntervalWaitForIt() {
    let settings = LiveLocationSettings.of(.coarse)

    XCTAssertFalse(
      settings.forwards(location(), now: now, lastForwardAt: now.addingTimeInterval(-299)))
    XCTAssertTrue(
      settings.forwards(location(), now: now, lastForwardAt: now.addingTimeInterval(-300)))
  }

  func testAClockMovedBackDoesNotStallForwarding() {
    XCTAssertTrue(
      LiveLocationSettings.of(.coarse).forwards(
        location(), now: now, lastForwardAt: now.addingTimeInterval(600)))
  }

  func testCaptureOutlivesTheShareOnlyByAShortGrace() {
    XCTAssertFalse(LiveLocationSettings.isPastEnd(now: now.addingTimeInterval(120), endsAt: now))
    XCTAssertTrue(LiveLocationSettings.isPastEnd(now: now.addingTimeInterval(121), endsAt: now))
  }

  func testTheEndIsReadFromTheNoticeDartSends() {
    XCTAssertEqual(
      LiveLocationSettings.endsAt(ofNotice: ["title": "Sharing", "endsAtMs": 1_700_000_000_250]),
      Date(timeIntervalSince1970: 1_700_000_000.25))
    XCTAssertNil(LiveLocationSettings.endsAt(ofNotice: nil))
    XCTAssertNil(LiveLocationSettings.endsAt(ofNotice: ["endsAtMs": "soon"]))
  }

  func testAFixReachesDartAsTheChannelContractNamesIt() {
    let fix = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4), altitude: 0,
      horizontalAccuracy: 12, verticalAccuracy: -1,
      timestamp: Date(timeIntervalSince1970: 1_700_000_000.25))

    let map = LiveLocationSettings.fix(fix, seq: 7)

    XCTAssertEqual(map["lat"] as? Double, 52.5)
    XCTAssertEqual(map["lon"] as? Double, 13.4)
    XCTAssertEqual(map["accuracy"] as? Double, 12)
    XCTAssertEqual(map["ts"] as? Int64, 1_700_000_000_250)
    XCTAssertEqual(map["seq"] as? Int, 7)
  }
}
