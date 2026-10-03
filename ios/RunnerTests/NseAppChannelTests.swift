import XCTest

@testable import Runner

final class NseAppChannelTests: XCTestCase {
  func testTheAppMethodsReadTheirArguments() throws {
    guard
      case .writeShown(let keys) = try XCTUnwrap(
        NseAppRequest(method: "writeShown", arguments: ["e": ["$a", "invite:!r"]]))
    else { return XCTFail("not writeShown") }
    XCTAssertEqual(keys, ["$a", "invite:!r"])

    guard
      case .setCredential(let credential, let expires) = try XCTUnwrap(
        NseAppRequest(
          method: "setCredential",
          arguments: ["credential": "c", "expires_ts": NSNumber(value: 1_792_592_000_000)]))
    else { return XCTFail("not setCredential") }
    XCTAssertEqual(credential, "c")
    XCTAssertEqual(expires, 1_792_592_000_000)

    guard
      case .syncBadge(let unread) = try XCTUnwrap(
        NseAppRequest(method: "syncBadge", arguments: ["unread": ["t1"]]))
    else { return XCTFail("not syncBadge") }
    XCTAssertEqual(unread, ["t1"])
  }

  func testClearingTheCredentialAndBareMethodsNeedNoArguments() throws {
    guard
      case .setCredential(let credential, let expires) = try XCTUnwrap(
        NseAppRequest(method: "setCredential", arguments: ["credential": NSNull()]))
    else { return XCTFail("not setCredential") }
    XCTAssertNil(credential)
    XCTAssertNil(expires)
    XCTAssertNotNil(NseAppRequest(method: "takeMarks", arguments: nil))
    XCTAssertNotNil(NseAppRequest(method: "readOutcomes", arguments: nil))
  }

  func testPhaseTwoAndUnknownMethodsAreLeftToTheirOwner() {
    for method in ["threadKey", "writeMeta", "writeRoom", "deleteRoom", "wipe", "removeDelivered"] {
      XCTAssertNil(NseAppRequest(method: method, arguments: [:]), method)
    }
  }

  func testATapOpensTheRoomBehindTheToken() {
    let known = String(repeating: "a1", count: 16)
    let unknown = String(repeating: "b9", count: 16)
    let resolve: (String) -> String? = { $0 == known ? "!abc:zuno.im" : nil }

    XCTAssertEqual(
      NotificationResponseRoute.roomId(in: ["t": known, "k": "msg"], resolveToken: resolve),
      "!abc:zuno.im")
    XCTAssertEqual(
      NotificationResponseRoute.roomId(in: ["t": unknown], resolveToken: resolve), "t:" + unknown)
    XCTAssertEqual(
      NotificationResponseRoute.roomId(
        in: ["room_id": "!static:zuno.im", "t": known], resolveToken: resolve),
      "!static:zuno.im")
    XCTAssertNil(NotificationResponseRoute.roomId(in: ["t": ""], resolveToken: resolve))
  }

  func testATokenThatIsNotThirtyTwoLowercaseHexCharactersOpensNothing() {
    let resolve: (String) -> String? = { _ in "!abc:zuno.im" }
    let valid = String(repeating: "0f", count: 16)

    XCTAssertEqual(
      NotificationResponseRoute.roomId(in: ["t": valid], resolveToken: resolve), "!abc:zuno.im")
    for token in ["../x", valid.uppercased(), String(valid.dropFirst()), valid + "0"] {
      XCTAssertNil(
        NotificationResponseRoute.roomId(in: ["t": token], resolveToken: resolve), token)
    }
  }
}
