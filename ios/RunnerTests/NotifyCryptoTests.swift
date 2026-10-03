import CryptoKit
import XCTest

@testable import Runner

enum ContractFixture {
  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("test/fixtures/push", isDirectory: true)

  static func load(_ name: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(
      with: Data(contentsOf: directory.appendingPathComponent(name)))
    return try XCTUnwrap(object as? [String: Any], name)
  }

  static func bytes(_ value: Any?) throws -> Data {
    let text = try XCTUnwrap(value as? String)
    return try XCTUnwrap(Data(base64Encoded: text), text)
  }
}

final class SealedFileTests: XCTestCase {
  private func contract() throws -> (
    cases: [[String: Any]], tamper: [[String: Any]], key: SymmetricKey
  ) {
    let fixture = try ContractFixture.load("sealed_file_v1.json")
    return (
      try XCTUnwrap(fixture["cases"] as? [[String: Any]]),
      try XCTUnwrap(fixture["tamper"] as? [[String: Any]]),
      SymmetricKey(data: try ContractFixture.bytes(fixture["rm_key"]))
    )
  }

  func testEveryContractCaseSealsToItsExactBytesAndOpens() throws {
    let (cases, _, key) = try contract()
    XCTAssertFalse(cases.isEmpty)
    for entry in cases {
      let name = try XCTUnwrap(entry["name"] as? String)
      let plaintext = Data(try XCTUnwrap(entry["plaintext"] as? String).utf8)
      let sealed = try ContractFixture.bytes(entry["sealed"])
      let nonce = try ChaChaPoly.Nonce(data: ContractFixture.bytes(entry["nonce"]))

      XCTAssertEqual(
        try SealedFile.seal(plaintext, name: name, key: key, nonce: nonce), sealed, name)
      XCTAssertEqual(try SealedFile.open(sealed, name: name, key: key), plaintext, name)
    }
  }

  func testEveryContractTamperCaseIsRefused() throws {
    let (_, tamper, key) = try contract()
    XCTAssertGreaterThanOrEqual(tamper.count, 5)
    for entry in tamper {
      let name = entry["name"] as? String ?? "?"
      let sealed = try ContractFixture.bytes(entry["sealed"])
      let fileName = try XCTUnwrap(entry["file_name"] as? String, name)

      XCTAssertThrowsError(try SealedFile.open(sealed, name: fileName, key: key), name) {
        if name == "unknown_version" {
          XCTAssertEqual($0 as? SealedFileError, .unknownVersion)
        }
      }
    }
  }

  func testAFileShorterThanItsFramingIsTruncated() {
    let key = SymmetricKey(data: Data(0x40...0x5f))

    XCTAssertThrowsError(try SealedFile.open(Data([0x01, 0x02]), name: "meta", key: key)) {
      XCTAssertEqual($0 as? SealedFileError, .truncated)
    }
  }

  func testEachSealUsesAFreshNonce() throws {
    let key = SymmetricKey(data: Data(0x40...0x5f))
    let plaintext = Data(#"{"v":1}"#.utf8)
    let first = try SealedFile.seal(plaintext, name: "meta", key: key)
    let second = try SealedFile.seal(plaintext, name: "meta", key: key)

    XCTAssertNotEqual(first, second)
    XCTAssertEqual(try SealedFile.open(second, name: "meta", key: key), plaintext)
  }
}

final class OpaqueIdsTests: XCTestCase {
  private let installKey = SymmetricKey(data: Data(0x20...0x3f))

  func testEveryContractRoomAndEventTokenMatches() throws {
    let fixture = try ContractFixture.load("opaque_ids_v1.json")
    let key = SymmetricKey(data: try ContractFixture.bytes(fixture["install_key"]))
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    XCTAssertGreaterThanOrEqual(cases.count, 2)
    for entry in cases {
      let input = try XCTUnwrap(entry["input"])
      let token =
        entry["kind"] == "room"
        ? OpaqueIds.roomToken(input, installKey: key)
        : OpaqueIds.eventToken(input, installKey: key)

      XCTAssertEqual(token, entry["token"], input)
    }
  }

  func testTheRingTokenIsTheSameHmacOverTheCallUuid() {
    XCTAssertEqual(
      OpaqueIds.ringToken(
        CallIdentity.uuid(roomId: "!abc:zuno.im", callId: "c1"), installKey: installKey),
      "2bbdb71fa0ee304731d26ee70727454c")
  }

  func testAnotherInstallKeyGivesAnUnrelatedToken() {
    let other = SymmetricKey(data: Data(0x21...0x40))

    XCTAssertNotEqual(
      OpaqueIds.roomToken("!abc:zuno.im", installKey: other),
      "2d2de6b6c6565ad95bf365845db19da9")
  }

  func testTokensAreThirtyTwoLowercaseHexCharactersWithoutTheId() {
    let token = OpaqueIds.roomToken("@alice:zuno.im", installKey: installKey)

    XCTAssertEqual(token.count, 32)
    XCTAssertTrue(token.allSatisfy { "0123456789abcdef".contains($0) })
    XCTAssertFalse(token.contains("@"))
  }
}
