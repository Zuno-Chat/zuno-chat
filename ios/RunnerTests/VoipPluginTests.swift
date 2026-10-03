@preconcurrency import Flutter
import XCTest

@testable import Runner

@MainActor
final class VoipPluginFixture {
  let ring: RingFixture
  var environment = "development"
  var token: Data? = Data([0xa1, 0xb2, 0xc3, 0xd4])

  init(_ test: XCTestCase) throws {
    ring = try RingFixture(test)
    _ = ring.read.memory.delete(service: VoipKeyStore.service, accessGroup: nil)
  }

  var memory: MemoryKeychain { ring.read.memory }

  func plugin(kids: [UInt32] = [5, 6]) -> VoipPlugin {
    let queue = KidQueue(kids)
    return VoipPlugin(
      handler: ring.handler, keys: VoipKeyStore(backend: memory, newKid: { queue.next() }),
      environment: { [unowned self] in self.environment }, callKitAvailable: { true },
      token: { [unowned self] in self.token }, now: { Date(timeIntervalSince1970: 1) })
  }

  func call(_ plugin: VoipPlugin, _ method: String, _ arguments: [String: Any]? = nil) -> Any? {
    var reply: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { reply = $0 }
    return reply
  }
}

@MainActor
final class VoipPluginTests: XCTestCase {
  func testStatusHandsDartTheTokenEnvironmentAndAKeyItCreates() throws {
    let voip = try VoipPluginFixture(self)

    let status = try XCTUnwrap(voip.call(voip.plugin(), "status") as? [String: Any])

    XCTAssertEqual(
      status["token"] as? String, Data([0xa1, 0xb2, 0xc3, 0xd4]).base64EncodedString())
    XCTAssertEqual(status["environment"] as? String, "development")
    XCTAssertEqual(status["kid"] as? Int, 5)
    XCTAssertEqual((status["key"] as? String).flatMap { Data(base64Encoded: $0) }?.count, 32)
    XCTAssertEqual(status["callkit"] as? Bool, true)
  }

  func testWithoutATokenStatusSaysSoAndStillGivesTheKey() throws {
    let voip = try VoipPluginFixture(self)
    voip.token = nil

    let status = try XCTUnwrap(voip.call(voip.plugin(), "status") as? [String: Any])

    XCTAssertTrue(status["token"] is NSNull)
    XCTAssertEqual(status["kid"] as? Int, 5)
  }

  func testBeforeFirstUnlockStatusIsAnError() throws {
    let voip = try VoipPluginFixture(self)
    voip.memory.locked = true

    XCTAssertEqual((voip.call(voip.plugin(), "status") as? FlutterError)?.code, "keychain")
  }

  func testRotationAndAcknowledgementReachTheKeyStore() throws {
    let voip = try VoipPluginFixture(self)
    let plugin = voip.plugin()
    _ = voip.call(plugin, "status")

    let rotated = try XCTUnwrap(voip.call(plugin, "rotateKey") as? [String: Any])
    XCTAssertNil(voip.call(plugin, "ackKey", ["kid": 6]))

    XCTAssertEqual(rotated["kid"] as? Int, 6)
    guard case .ready(let keys) = VoipKeyStore(backend: voip.memory).load() else {
      return XCTFail("no key")
    }
    XCTAssertEqual(keys.prevKid, 5)
    XCTAssertEqual(keys.prevUntilMs, 1_000 + VoipKeyStore.previousKeyGrace)
  }

  func testEventsAreTakenAsTypedMaps() throws {
    let voip = try VoipPluginFixture(self)
    voip.ring.handler.tokenUpdated(Data([9]))

    let events = try XCTUnwrap(voip.call(voip.plugin(), "takeEvents") as? [[String: String]])

    XCTAssertEqual(events, [["type": "token"]])
  }

  func testTheSessionSwitchReachesTheHandler() throws {
    let voip = try VoipPluginFixture(self)
    let plugin = voip.plugin()
    _ = voip.call(plugin, "status")

    XCTAssertNil(voip.call(plugin, "setSession", ["signedIn": false]))
    XCTAssertEqual(VoipKeyStore(backend: voip.memory).load(), .missing)
    XCTAssertEqual(voip.ring.cache.signedOut(), .present)
  }

  func testADevelopmentBuildExportsTheTestValuesWithAHexToken() throws {
    let voip = try VoipPluginFixture(self)
    let plugin = voip.plugin()
    _ = voip.call(plugin, "status")

    let export = try XCTUnwrap(voip.call(plugin, "devExport") as? [String: Any])

    XCTAssertEqual(export["token"] as? String, "a1b2c3d4")
    XCTAssertEqual(export["kid"] as? Int, 5)
    XCTAssertEqual((export["key"] as? String).flatMap { Data(base64Encoded: $0) }?.count, 32)
    XCTAssertEqual(export["environment"] as? String, "development")
  }

  func testAProductionBuildNeverExportsTheTestValues() throws {
    let voip = try VoipPluginFixture(self)
    voip.environment = "production"
    let plugin = voip.plugin()
    _ = voip.call(plugin, "status")

    XCTAssertNil(voip.call(plugin, "devExport"))
    XCTAssertNil(plugin.devExport())
  }

  func testNothingIsExportedWithoutAToken() throws {
    let voip = try VoipPluginFixture(self)
    voip.token = nil
    let plugin = voip.plugin()
    _ = voip.call(plugin, "status")

    XCTAssertNil(plugin.devExport())
  }
}
