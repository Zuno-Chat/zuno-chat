import XCTest

@testable import Runner

final class PushEnvironmentTests: XCTestCase {
  private func signed(_ plist: String) -> Data {
    Data([0x30, 0x82, 0x3C, 0x00, 0xFF, 0x06, 0x09]) + Data(plist.utf8)
      + Data([0xA0, 0x82, 0x01, 0x3C, 0x2F, 0x00])
  }

  private func profile(apsEnvironment: String?) -> Data {
    let push = apsEnvironment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>Name</key><string>Zuno Development</string>
      <key>Entitlements</key><dict>\(push)<key>get-task-allow</key><true/></dict>
      </dict></plist>
      """
    return signed(plist)
  }

  private func profile(root: String) -> Data {
    signed("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\">\(root)</plist>")
  }

  func testADevelopmentProfileOnADevicePicksDevelopment() {
    XCTAssertEqual(
      PushEnvironment.resolve(profile: profile(apsEnvironment: "development"), simulator: false),
      .development)
  }

  func testAProductionProfileOnADevicePicksProduction() {
    XCTAssertEqual(
      PushEnvironment.resolve(profile: profile(apsEnvironment: "production"), simulator: false),
      .production)
  }

  func testNoProfileOnADeviceIsAStoreOrTestFlightBuildAndPicksProduction() {
    XCTAssertEqual(PushEnvironment.resolve(profile: nil, simulator: false), .production)
  }

  func testAProfileWithoutPushPicksProduction() {
    XCTAssertEqual(
      PushEnvironment.resolve(profile: profile(apsEnvironment: nil), simulator: false), .production)
  }

  func testBytesThatAreNotAProfilePickProduction() {
    let unreadable = [
      Data(repeating: 0xFF, count: 64),
      Data("<?xml version=\"1.0\"?><plist><dict>".utf8),
      Data("<?xml version=\"1.0\"?><plist>not a plist</plist>".utf8),
      Data(),
    ]
    for data in unreadable {
      XCTAssertEqual(PushEnvironment.resolve(profile: data, simulator: false), .production)
    }
  }

  func testAProfileWhoseRootIsNotADictionaryPicksProduction() {
    let roots = [
      "<array><string>development</string></array>",
      "<string>development</string>",
    ]
    for root in roots {
      let data = profile(root: root)
      XCTAssertNil(PushEnvironment.entitlements(in: data), root)
      XCTAssertEqual(PushEnvironment.resolve(profile: data, simulator: false), .production, root)
    }
  }

  func testAProfileWithoutADictionaryOfEntitlementsPicksProduction() {
    let push = "<key>aps-environment</key><string>development</string>"
    let roots = [
      "<dict>\(push)</dict>",
      "<dict><key>Entitlements</key><string>development</string>\(push)</dict>",
      "<dict><key>Entitlements</key><array><dict>\(push)</dict></array></dict>",
    ]
    for root in roots {
      let data = profile(root: root)
      XCTAssertNil(PushEnvironment.entitlements(in: data), root)
      XCTAssertEqual(PushEnvironment.resolve(profile: data, simulator: false), .production, root)
    }
  }

  func testAPushEnvironmentThatIsNotAStringPicksProduction() {
    let values = [
      "<true/>",
      "<integer>1</integer>",
      "<array><string>development</string></array>",
    ]
    for value in values {
      let data = profile(
        root: "<dict><key>Entitlements</key><dict><key>aps-environment</key>\(value)</dict></dict>"
      )
      XCTAssertNotNil(PushEnvironment.entitlements(in: data)?["aps-environment"], value)
      XCTAssertEqual(PushEnvironment.resolve(profile: data, simulator: false), .production, value)
    }
  }

  func testTheSimulatorAlwaysPicksDevelopment() {
    XCTAssertEqual(PushEnvironment.resolve(profile: nil, simulator: true), .development)
    XCTAssertEqual(
      PushEnvironment.resolve(profile: profile(apsEnvironment: "production"), simulator: true),
      .development)
  }

  func testTheEntitlementsAreReadFromBetweenTheSignatureBytes() {
    XCTAssertEqual(
      PushEnvironment.entitlements(in: profile(apsEnvironment: "development"))?["aps-environment"]
        as? String, "development")
  }

  func testTheTestHostIsASimulatorBuildAndPicksDevelopment() {
    XCTAssertEqual(PushEnvironment.current, .development)
    XCTAssertEqual(PushEnvironment.current.rawValue, "development")
  }
}
