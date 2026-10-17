import UIKit
import XCTest

@testable import Runner

@MainActor
final class KeyboardPolicyTests: XCTestCase {
  override func setUp() {
    super.setUp()
    KeyboardPolicy.allowsThirdParty = false
  }

  override func tearDown() {
    KeyboardPolicy.allowsThirdParty = false
    super.tearDown()
  }

  func testOtherKeyboardsAreBlockedWhileIncognitoKeyboardIsOn() {
    XCTAssertFalse(KeyboardPolicy.allows(.keyboard))
  }

  func testTurningIncognitoKeyboardOffAllowsOtherKeyboards() {
    KeyboardPolicy.allowsThirdParty = true
    XCTAssertTrue(KeyboardPolicy.allows(.keyboard))
  }

  func testTheAppAnswersIOSBothWays() throws {
    let delegate = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
    XCTAssertFalse(delegate.application(.shared, shouldAllowExtensionPointIdentifier: .keyboard))

    KeyboardPolicy.allowsThirdParty = true

    XCTAssertTrue(delegate.application(.shared, shouldAllowExtensionPointIdentifier: .keyboard))
  }
}
