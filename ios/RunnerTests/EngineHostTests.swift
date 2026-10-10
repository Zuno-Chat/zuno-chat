@preconcurrency import Flutter
import XCTest

@testable import Runner

@MainActor
final class EngineFixture {
  var launches: [(arguments: [String], headless: Bool)] = []
  var canStart = true

  func host() -> EngineHost {
    EngineHost(
      launch: { [unowned self] arguments, headless in
        self.launches.append((arguments, headless))
        return FlutterEngine(name: "test-\(UUID().uuidString)", project: nil)
      },
      canStart: { [unowned self] in self.canStart })
  }
}

@MainActor
final class EngineHostTests: XCTestCase {
  func testARingStartsOneHeadlessEngineThatTheSceneLaterShares() {
    let fixture = EngineFixture()
    let host = fixture.host()

    let ring = host.start(.ring)
    let scene = host.start(.scene)

    XCTAssertTrue(ring === scene)
    XCTAssertEqual(fixture.launches.map(\.arguments), [["--zuno-wake=ring"]])
    XCTAssertEqual(fixture.launches.map(\.headless), [true])
  }

  func testASceneStartsTheEngineWithNoWakeReason() {
    let fixture = EngineFixture()
    let host = fixture.host()

    _ = host.start(.scene)

    XCTAssertEqual(fixture.launches.map(\.arguments), [[]])
    XCTAssertEqual(fixture.launches.map(\.headless), [false])
    XCTAssertNil(host.takeWakeReason())
  }

  func testTheWakeReasonIsTakenOnce() {
    let fixture = EngineFixture()
    let host = fixture.host()
    _ = host.start(.ring)

    XCTAssertEqual(host.takeWakeReason(), "ring")
    XCTAssertNil(host.takeWakeReason())
  }

  func testAPrewarmBeforeFirstUnlockStartsNothing() {
    let fixture = EngineFixture()
    fixture.canStart = false
    let host = fixture.host()

    host.startForRing()

    XCTAssertTrue(fixture.launches.isEmpty)
    XCTAssertNil(host.engine)
  }

  func testAPrewarmAfterUnlockStartsTheEngineOnce() {
    let fixture = EngineFixture()
    let host = fixture.host()

    host.startForRing()
    host.startForRing()

    XCTAssertEqual(fixture.launches.count, 1)
    XCTAssertNotNil(host.engine)
  }

  func testWakeArgumentsNameTheReason() {
    XCTAssertEqual(EngineHost.arguments(for: .scene), [])
    XCTAssertEqual(EngineHost.arguments(for: .ring), ["--zuno-wake=ring"])
    XCTAssertEqual(EngineHost.arguments(for: .action), ["--zuno-wake=action"])
  }
}

@MainActor
final class LaunchPluginTests: XCTestCase {
  func testTheWakeReasonAndDiagnosticsArePulledOnce() {
    let host = EngineHost(
      launch: { _, _ in FlutterEngine(name: "test-launch", project: nil) }, canStart: { true })
    _ = host.start(.ring)
    let defaults = UserDefaults(suiteName: "launch-\(UUID().uuidString)")!
    let metrics = MetricsSubscriber(defaults: defaults, log: { _ in })
    metrics.record(["pushkit_unreported code=0xbaadca11"])
    let plugin = LaunchPlugin(host: host, diagnostics: metrics)

    let replies = ["takeWakeReason", "takeWakeReason", "takeDiagnostics", "takeDiagnostics"].map {
      immediateReply(from: plugin, method: $0)
    }

    XCTAssertEqual(replies[0] as? String, "ring")
    XCTAssertNil(replies[1])
    XCTAssertEqual(replies[2] as? [String], ["pushkit_unreported code=0xbaadca11"])
    XCTAssertEqual(replies[3] as? [String], [])
  }
}

final class MetricKitLineTests: XCTestCase {
  func testAnUnreportedVoipPushKillIsNamedAsItsSummaryCountsIt() {
    XCTAssertEqual(
      MetricKitLine.line(
        terminationReason: "Namespace RUNNINGBOARD, Code 0xbaadca11", exceptionType: 10,
        signal: 9),
      "\(MetricSummaries.pushkitUnreported) exception=10 signal=9 code=0xbaadca11")
  }

  func testAnyOtherCrashKeepsOnlyItsCodes() {
    XCTAssertEqual(
      MetricKitLine.line(terminationReason: nil, exceptionType: 1, signal: 11),
      "crash exception=1 signal=11")
  }

  func testOnlyTheNewestTwentyLinesWaitAndTakingThemEmptiesTheQueue() {
    let defaults = UserDefaults(suiteName: "metrics-\(UUID().uuidString)")!
    let metrics = MetricsSubscriber(defaults: defaults, log: { _ in })

    metrics.record((0..<25).map { "crash n=\($0)" })

    let pending = metrics.takePending()
    XCTAssertEqual(pending.count, 20)
    XCTAssertEqual(pending.first, "crash n=5")
    XCTAssertEqual(metrics.takePending(), [])
  }
}
