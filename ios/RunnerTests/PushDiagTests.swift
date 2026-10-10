@preconcurrency import Flutter
import UserNotifications
import XCTest

@testable import Runner

final class PushDiagTests: XCTestCase {
  private let snapshot = NotificationSettingsSnapshot(
    authorization: .provisional,
    alert: .enabled,
    sound: .disabled,
    badge: .enabled,
    lockScreen: .disabled,
    notificationCenter: .enabled,
    carPlay: .notSupported,
    criticalAlert: .notSupported,
    announcement: .disabled,
    timeSensitive: .enabled,
    scheduledDelivery: .disabled,
    directMessages: .notSupported,
    alertStyle: .banner,
    showPreviews: .whenAuthenticated,
    providesAppSettings: false)

  func testEveryPermissionStateHasTheNameDartReads() {
    let names = [
      UNAuthorizationStatus.notDetermined, .denied, .authorized, .provisional, .ephemeral,
    ].map(NotificationSettingsSnapshot.name)
    XCTAssertEqual(names, ["notDetermined", "denied", "authorized", "provisional", "ephemeral"])
  }

  func testEverySettingStyleAndPreviewHasTheNameDartReads() {
    XCTAssertEqual(
      [UNNotificationSetting.notSupported, .disabled, .enabled].map(
        NotificationSettingsSnapshot.name), ["notSupported", "disabled", "enabled"])
    XCTAssertEqual(
      [UNAlertStyle.none, .banner, .alert].map(NotificationSettingsSnapshot.name),
      ["none", "banner", "alert"])
    XCTAssertEqual(
      [UNShowPreviewsSetting.always, .whenAuthenticated, .never].map(
        NotificationSettingsSnapshot.name), ["always", "whenAuthenticated", "never"])
  }

  func testAValueAddedInALaterIosReadsAsUnknown() {
    XCTAssertEqual(
      NotificationSettingsSnapshot.name(UNAuthorizationStatus(rawValue: 99)!), "unknown")
    XCTAssertEqual(
      NotificationSettingsSnapshot.name(UNNotificationSetting(rawValue: 99)!), "unknown")
  }

  func testTheSnapshotCarriesEveryFieldOfTheSettings() {
    let dictionary = PushDiagSnapshot.dictionary(
      settings: snapshot, environment: .development, registered: true)
    let settings = dictionary["settings"] as? [String: Any]

    XCTAssertEqual(dictionary["environment"] as? String, "development")
    XCTAssertEqual(dictionary["registeredForRemoteNotifications"] as? Bool, true)
    XCTAssertEqual(
      settings?.compactMapValues { $0 as? String },
      [
        "authorization": "provisional", "alert": "enabled", "sound": "disabled",
        "badge": "enabled", "lockScreen": "disabled", "notificationCenter": "enabled",
        "carPlay": "notSupported", "criticalAlert": "notSupported", "announcement": "disabled",
        "timeSensitive": "enabled", "scheduledDelivery": "disabled",
        "directMessages": "notSupported", "alertStyle": "banner",
        "showPreviews": "whenAuthenticated",
      ])
    XCTAssertEqual(settings?["providesAppSettings"] as? Bool, false)
    XCTAssertEqual(settings?.count, 15)
  }
}

@MainActor
extension PushDiagTests {
  func testTheEnvironmentAndTheRegistrationAreTheOnesGiven() {
    let dictionary = PushDiagSnapshot.dictionary(
      settings: snapshot, environment: .production, registered: false)

    XCTAssertEqual(dictionary["environment"] as? String, "production")
    XCTAssertEqual(dictionary["registeredForRemoteNotifications"] as? Bool, false)
  }

  func testTheSnapshotMethodAnswersTheSettingsEnvironmentAndRegistrationOnTheMainThread() async {
    let outcome = await channelReply(from: PushDiagPlugin(), method: "snapshot")
    let dictionary = outcome.answer as? [String: Any]

    XCTAssertTrue(outcome.onMainThread)
    XCTAssertEqual((dictionary?["settings"] as? [String: Any])?.count, 15)
    XCTAssertEqual(dictionary?["environment"] as? String, PushEnvironment.current.rawValue)
    XCTAssertNotNil(dictionary?["registeredForRemoteNotifications"] as? Bool)
  }

  func testAnUnknownMethodIsNotImplemented() async {
    for method in ["unknown", "Snapshot", ""] {
      let outcome = await channelReply(from: PushDiagPlugin(), method: method)
      XCTAssertIdentical(outcome.answer as? NSObject, FlutterMethodNotImplemented, method)
    }
  }
}
