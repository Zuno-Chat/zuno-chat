import CoreLocation
@preconcurrency import Flutter
import UIKit

enum LiveLocationMode: String, Sendable {
  case coarse
  case precise
}

struct LiveLocationSettings: Equatable, Sendable {
  static let maxFixAge: TimeInterval = 60
  static let endGrace: TimeInterval = 120

  let desiredAccuracy: CLLocationAccuracy
  let forwardInterval: TimeInterval

  static func of(_ mode: LiveLocationMode) -> LiveLocationSettings {
    switch mode {
    case .coarse:
      LiveLocationSettings(desiredAccuracy: kCLLocationAccuracyHundredMeters, forwardInterval: 300)
    case .precise:
      LiveLocationSettings(desiredAccuracy: kCLLocationAccuracyBest, forwardInterval: 5)
    }
  }

  func forwards(_ location: CLLocation, now: Date, lastForwardAt: Date?) -> Bool {
    guard location.horizontalAccuracy >= 0,
      abs(now.timeIntervalSince(location.timestamp)) <= Self.maxFixAge
    else { return false }
    guard let lastForwardAt else { return true }
    let elapsed = now.timeIntervalSince(lastForwardAt)
    return elapsed < 0 || elapsed >= forwardInterval
  }

  static func isPastEnd(now: Date, endsAt: Date) -> Bool {
    now.timeIntervalSince(endsAt) > endGrace
  }

  static func endsAt(ofNotice notice: Any?) -> Date? {
    guard let milliseconds = ((notice as? [String: Any])?["endsAtMs"] as? NSNumber)?.doubleValue
    else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
  }

  static func fix(_ location: CLLocation, seq: Int) -> [String: Any] {
    var fix: [String: Any] = [
      "lat": location.coordinate.latitude,
      "lon": location.coordinate.longitude,
      "ts": Int64((location.timestamp.timeIntervalSince1970 * 1000).rounded()),
      "seq": seq,
    ]
    if location.horizontalAccuracy >= 0 { fix["accuracy"] = location.horizontalAccuracy }
    return fix
  }
}

@MainActor
final class LiveLocationPlugin: NSObject, @preconcurrency FlutterPlugin,
  @preconcurrency FlutterStreamHandler
{
  private let manager = CLLocationManager()
  private var sink: FlutterEventSink?
  private var settings = LiveLocationSettings.of(.coarse)
  private var running = false
  private var seq = 0
  private var lastForwardAt: Date?
  private var endsAt: Date?
  private var dartHold = UIBackgroundTaskIdentifier.invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = LiveLocationPlugin()
    registrar.addMethodCallDelegate(
      plugin,
      channel: FlutterMethodChannel(
        name: "zuno/live_location", binaryMessenger: registrar.messenger()))
    FlutterEventChannel(name: "zuno/live_location/fixes", binaryMessenger: registrar.messenger())
      .setStreamHandler(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let mode = (arguments?["mode"] as? String).flatMap(LiveLocationMode.init(rawValue:))
    switch call.method {
    case "start":
      guard let mode else {
        result(FlutterError(code: "bad_args", message: "mode is required", details: nil))
        return
      }
      guard authorized(manager.authorizationStatus) else {
        result(FlutterError(code: "denied", message: "location access is missing", details: nil))
        return
      }
      start(mode, endsAt: LiveLocationSettings.endsAt(ofNotice: arguments?["notice"]))
      result(nil)
    case "setMode":
      if let mode, running { apply(mode) }
      result(nil)
    case "updateNotice":
      if let endsAt = LiveLocationSettings.endsAt(ofNotice: call.arguments) {
        self.endsAt = endsAt
      }
      result(nil)
    case "releaseWakeLock":
      result(nil)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func authorized(_ status: CLAuthorizationStatus) -> Bool {
    status == .authorizedWhenInUse || status == .authorizedAlways
  }

  private func start(_ mode: LiveLocationMode, endsAt: Date?) {
    endDartHold()
    self.endsAt = endsAt
    manager.delegate = self
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.pausesLocationUpdatesAutomatically = false
    manager.activityType = .other
    manager.distanceFilter = kCLDistanceFilterNone
    running = true
    lastForwardAt = nil
    apply(mode)
    manager.startUpdatingLocation()
  }

  private func apply(_ mode: LiveLocationMode) {
    settings = LiveLocationSettings.of(mode)
    manager.desiredAccuracy = settings.desiredAccuracy
  }

  private func stop() {
    halt()
    endDartHold()
  }

  private func halt() {
    running = false
    lastForwardAt = nil
    manager.stopUpdatingLocation()
    manager.allowsBackgroundLocationUpdates = false
  }

  private func deliver(_ location: CLLocation) {
    guard running else { return }
    let now = Date()
    if let endsAt, LiveLocationSettings.isPastEnd(now: now, endsAt: endsAt) {
      lose("ended")
      return
    }
    guard settings.forwards(location, now: now, lastForwardAt: lastForwardAt) else { return }
    lastForwardAt = now
    seq += 1
    sink?(LiveLocationSettings.fix(location, seq: seq))
  }

  private func lose(_ code: String) {
    guard running else { return }
    holdForDart()
    halt()
    sink?(["error": code])
  }

  private func holdForDart() {
    guard dartHold == .invalid else { return }
    dartHold = UIApplication.shared.beginBackgroundTask(withName: "zuno.live_location.lost") {
      [weak self] in self?.endDartHold()
    }
  }

  private func endDartHold() {
    guard dartHold != .invalid else { return }
    UIApplication.shared.endBackgroundTask(dartHold)
    dartHold = .invalid
  }
}

extension LiveLocationPlugin: @preconcurrency CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    deliver(location)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    if (error as? CLError)?.code == .denied { lose("denied") }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if !authorized(manager.authorizationStatus) { lose("denied") }
  }
}
