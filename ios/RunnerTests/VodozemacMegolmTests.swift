import XCTest

@testable import Runner

final class VodozemacMegolmTests: XCTestCase {
  private var golden: NseJson!
  private let megolm = NseFixtures.vodozemac()

  override func setUpWithError() throws {
    golden = try NseFixtures.json("megolm_golden_v1.json")
  }

  private func ciphertext(_ index: Int) throws -> String {
    try XCTUnwrap(golden["ciphertexts"]?.array?[index].string)
  }

  private func plaintext(_ index: Int) throws -> String {
    try XCTUnwrap(golden["plaintexts"]?.array?[index].string)
  }

  private func string(_ key: String) throws -> String {
    try XCTUnwrap(golden[key]?.string)
  }

  func testTheAppsEmbeddedLibraryExportsTheDecryptFunctions() {
    XCTAssertTrue(megolm.isAvailable)
  }

  func testDecryptsTheDartPickledSessionFromItsTrimPoint() throws {
    let user = try string("user_id")
    let pickle = try string("pickle")

    for index in [2, 3] {
      XCTAssertEqual(
        megolm.decrypt(pickle: pickle, userId: user, ciphertext: try ciphertext(index)),
        .plaintext(try plaintext(index)))
    }
  }

  func testRefusesMessagesBeforeTheTrimPoint() throws {
    for index in [0, 1] {
      XCTAssertEqual(
        megolm.decrypt(
          pickle: try string("pickle"), userId: try string("user_id"),
          ciphertext: try ciphertext(index)),
        .failed)
    }
  }

  func testTheUntrimmedSessionStillDecryptsEverything() throws {
    XCTAssertEqual(
      megolm.decrypt(
        pickle: try string("pickle_full"), userId: try string("user_id"),
        ciphertext: try ciphertext(0)),
      .plaintext(try plaintext(0)))
  }

  func testAnotherSessionOrAnotherUsersKeyCannotDecrypt() throws {
    XCTAssertEqual(
      megolm.decrypt(
        pickle: try string("other_pickle"), userId: try string("user_id"),
        ciphertext: try ciphertext(3)),
      .failed)
    XCTAssertEqual(
      megolm.decrypt(
        pickle: try string("pickle"), userId: "@someone:zuno.im", ciphertext: try ciphertext(3)),
      .failed)
  }

  func testRejectsOversizeEmptyAndNulInputsBeforeCallingTheLibrary() throws {
    let pickle = try string("pickle")
    let user = try string("user_id")

    XCTAssertEqual(
      megolm.decrypt(
        pickle: pickle, userId: user,
        ciphertext: String(repeating: "A", count: VodozemacMegolm.maxCiphertextBytes + 1)),
      .rejected)
    XCTAssertEqual(
      megolm.decrypt(
        pickle: String(repeating: "A", count: VodozemacMegolm.maxPickleBytes + 1), userId: user,
        ciphertext: try ciphertext(3)),
      .rejected)
    XCTAssertEqual(megolm.decrypt(pickle: pickle, userId: user, ciphertext: ""), .rejected)
    XCTAssertEqual(
      megolm.decrypt(pickle: pickle + "\u{0}", userId: user, ciphertext: try ciphertext(3)),
      .rejected)
  }

  func testAMissingLibraryIsUnavailable() {
    let missing = VodozemacMegolm(path: "/nonexistent/flutter_vodozemac")

    XCTAssertFalse(missing.isAvailable)
    XCTAssertEqual(missing.decrypt(pickle: "p", userId: "@a:b", ciphertext: "c"), .unavailable)
  }

  func testThePickleKeyIsTheUserIdPaddedOrCutLikeTheSdk() {
    XCTAssertEqual(
      MegolmPickleKey.forUser("@a:b"),
      Array("@a:b".utf8) + [UInt8](repeating: 0, count: 28))
    let long = "@" + String(repeating: "x", count: 40) + ":zuno.im"
    XCTAssertEqual(MegolmPickleKey.forUser(long), Array(long.utf8.prefix(32)))
  }
}
