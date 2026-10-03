import XCTest

@testable import Runner

final class MegolmIndexTests: XCTestCase {
  func testReadsTheIndexOfRealCiphertexts() throws {
    let golden = try NseFixtures.json("megolm_golden_v1.json")
    let ciphertexts = try XCTUnwrap(golden["ciphertexts"]?.array?.compactMap(\.string))

    XCTAssertEqual(
      ciphertexts.map { MegolmIndex.messageIndex(ofCiphertext: $0) }, [0, 1, 2, 3])
  }

  func testReadsMultiByteIndexes() {
    XCTAssertEqual(MegolmIndex.messageIndex(ofCiphertext: "AwiWARIA"), 150)
    XCTAssertEqual(MegolmIndex.messageIndex(ofCiphertext: "Awj/////DxI"), UInt32.max)
  }

  func testRejectsOtherVersionsFieldsAndGarbage() {
    for ciphertext in ["AQgAEgA", "AxAAEgA", "AwiAgA", "AwiAgICAEBI", "", "A", "not base64!"] {
      XCTAssertNil(MegolmIndex.messageIndex(ofCiphertext: ciphertext), ciphertext)
    }
  }
}
