import CryptoKit
import XCTest

@testable import Runner

final class PushVectorTests: XCTestCase {
  private enum Outcome: String {
    case open
    case forged
    case generic
  }

  private func fixture(_ name: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("test/fixtures/push/\(name)")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return try XCTUnwrap(object as? [String: Any], name)
  }

  private func bytes(_ base64: Any?) throws -> [UInt8] {
    let text = try XCTUnwrap(base64 as? String)
    return Array(try XCTUnwrap(Data(base64Encoded: text), text))
  }

  private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  private func openBlob(_ blob: [UInt8], key: [UInt8]) throws -> [UInt8] {
    let box = try ChaChaPoly.SealedBox(combined: Data(blob[9...]))
    let aad = Array("zuno-voip-v1".utf8) + Array(blob[0..<9])
    return Array(try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: aad))
  }

  private func receive(_ text: String, key: [UInt8], kid: Int) -> Outcome {
    guard let data = Data(base64Encoded: text) else { return .forged }
    let blob = [UInt8](data)
    guard blob.count >= 9 else { return .forged }
    let blobKid = blob[1..<5].reduce(0) { $0 << 8 | Int($1) }
    guard blob[0] == 0x01, blobKid == kid else { return .generic }
    guard [512, 1024].contains(blob.count - 37) else { return .forged }
    return (try? openBlob(blob, key: key)) == nil ? .forged : .open
  }

  private func openFile(_ sealed: [UInt8], name: String, key: [UInt8]) throws -> [UInt8] {
    guard sealed.first == 0x01 else { throw CryptoKitError.incorrectParameterSize }
    let box = try ChaChaPoly.SealedBox(combined: Data(sealed.dropFirst()))
    return Array(
      try ChaChaPoly.open(
        box, using: SymmetricKey(data: key), authenticating: Array(name.utf8) + [0x01]))
  }

  private func normalizedName(_ name: String) -> String {
    var kept = String.UnicodeScalarView()
    var used = 0
    for scalar in name.unicodeScalars {
      switch scalar.value {
      case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
        continue
      default:
        let size = String(scalar).utf8.count
        guard used + size <= 64 else { return String(kept) }
        used += size
        kept.append(scalar)
      }
    }
    return String(kept)
  }

  func testEveryVoipVectorOpensToItsPlaintextPaddedWithZeros() throws {
    let fixture = try fixture("voip_blob_v1.json")
    let key = try bytes(fixture["key"])
    let kid = try XCTUnwrap(fixture["kid"] as? Int)
    let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
    XCTAssertEqual(vectors.count, 4)
    for vector in vectors {
      let text = try XCTUnwrap(vector["blob"] as? String)
      let blob = try bytes(text)
      let plaintext = Array(try XCTUnwrap(vector["plaintext"] as? String).utf8)
      let padded = try XCTUnwrap(vector["padded_length"] as? Int)
      let opened = try openBlob(blob, key: key)
      XCTAssertEqual(receive(text, key: key, kid: kid), .open)
      XCTAssertEqual(opened.count, padded)
      XCTAssertEqual(Array(opened.prefix(plaintext.count)), plaintext)
      XCTAssertTrue(opened.dropFirst(plaintext.count).allSatisfy { $0 == 0 })
      XCTAssertEqual(hex(SHA256.hash(data: blob)), vector["blob_sha256"] as? String)
    }
  }

  func testTheKnownAnswerSealsToTheContractBlob() throws {
    let fixture = try fixture("voip_blob_v1.json")
    let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
    let known = try XCTUnwrap(vectors.first { $0["name"] as? String == "known_answer" })
    let blob = try bytes(known["blob"])
    let plaintext = Array(try XCTUnwrap(known["plaintext"] as? String).utf8)
    let sealed = try ChaChaPoly.seal(
      plaintext + [UInt8](repeating: 0, count: 512 - plaintext.count),
      using: SymmetricKey(data: try bytes(fixture["key"])),
      nonce: ChaChaPoly.Nonce(data: try bytes(known["nonce"])),
      authenticating: Array("zuno-voip-v1".utf8) + Array(blob[0..<9]))
    XCTAssertEqual(Array(blob[21...]), Array(sealed.ciphertext) + Array(sealed.tag))
    XCTAssertEqual(
      hex(SHA256.hash(data: blob)),
      "aaf898f4941c4ff73dd0b30839264042535a098823be3a5ed024339fc58b6a80")
  }

  func testTheExpiryIsTheEarlierOfTheSendTimeAndThirtySecondsAfterReceiptPlus45() throws {
    let fixture = try fixture("voip_blob_v1.json")
    let key = try bytes(fixture["key"])
    let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
    XCTAssertEqual(vectors.filter { $0["name"] as? String == "skewed_sender" }.count, 1)
    for vector in vectors {
      let name = try XCTUnwrap(vector["name"] as? String)
      let blob = try bytes(vector["blob"])
      let opened = try openBlob(blob, key: key)
      let json = Data(opened.prefix(while: { $0 != 0 }))
      let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
      let ts = try XCTUnwrap(payload["ts"] as? Int)
      let rts = try XCTUnwrap(payload["rts"] as? Int)
      let expiry = blob[5..<9].reduce(0) { $0 << 8 | Int($1) }
      XCTAssertEqual(expiry, min(ts, rts + 30_000) / 1000 + 45, name)
      XCTAssertEqual(vector["x"] as? Int, expiry, name)
      if name == "skewed_sender" {
        XCTAssertGreaterThan(ts, rts + 30_000, name)
        XCTAssertNotEqual(expiry, ts / 1000 + 45, name)
      } else {
        XCTAssertLessThanOrEqual(ts, rts + 30_000, name)
        XCTAssertEqual(expiry, ts / 1000 + 45, name)
      }
    }
  }

  func testEveryTamperCaseIsReceivedAsTheFixtureExpects() throws {
    let fixture = try fixture("voip_blob_v1.json")
    let key = try bytes(fixture["key"])
    let kid = try XCTUnwrap(fixture["kid"] as? Int)
    let tampered = try XCTUnwrap(fixture["tamper"] as? [[String: String]])
    XCTAssertEqual(tampered.count, 9)
    for tamper in tampered {
      let name = tamper["name"] ?? ""
      let blob = try XCTUnwrap(tamper["blob"])
      XCTAssertEqual(receive(blob, key: key, kid: kid).rawValue, tamper["expect"], name)
    }
    let short = try XCTUnwrap(tampered.first { $0["name"] == "short_header" })
    XCTAssertLessThan(try bytes(short["blob"]).count, 9)
  }

  func testABlobOfAnotherPadLengthIsForgedEvenThoughItOpens() throws {
    let fixture = try fixture("voip_blob_v1.json")
    let key = try bytes(fixture["key"])
    let tampered = try XCTUnwrap(fixture["tamper"] as? [[String: String]])
    let unpadded = try XCTUnwrap(tampered.first { $0["name"] == "unpadded_length" })
    let blob = try bytes(unpadded["blob"])
    XCTAssertEqual(try openBlob(blob, key: key).count, 600)
    XCTAssertEqual(
      receive(try XCTUnwrap(unpadded["blob"]), key: key, kid: 16_909_060), .forged)
  }

  func testEveryNameLosesControlsAndKeepsWholeCharactersUpTo64Bytes() throws {
    let fixture = try fixture("names_v1.json")
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    XCTAssertEqual(cases.count, 21)
    for entry in cases {
      let output = try XCTUnwrap(entry["output"])
      XCTAssertEqual(normalizedName(try XCTUnwrap(entry["input"])), output, entry["name"] ?? "")
      XCTAssertLessThanOrEqual(output.utf8.count, 64)
    }
  }

  func testTheArabicLetterMarkIsStrippedAndTheCharactersJustOutsideTheRangesAreKept() throws {
    let fixture = try fixture("names_v1.json")
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    func entry(_ name: String) throws -> [String: String] {
      try XCTUnwrap(cases.first { $0["name"] == name }, name)
    }
    let stripped = try entry("arabic_letter_mark_stripped")
    let strippedInput = try XCTUnwrap(stripped["input"])
    XCTAssertTrue(strippedInput.unicodeScalars.contains { $0.value == 0x061C })
    XCTAssertEqual(stripped["output"], "Anais")
    let kept: [(String, UInt32)] = [
      ("no_break_space_kept", 0x00A0),
      ("just_below_isolates_kept", 0x2065),
      ("just_above_isolates_kept", 0x206A),
    ]
    for (name, value) in kept {
      let input = try XCTUnwrap(try entry(name)["input"])
      XCTAssertTrue(input.unicodeScalars.contains { $0.value == value }, name)
      XCTAssertEqual(try entry(name)["output"], input, name)
    }
  }

  func testCallIdentityGivesEveryFixtureUuid() throws {
    let fixture = try fixture("call_uuid_v5.json")
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    XCTAssertEqual(cases.count, 4)
    for entry in cases {
      let roomId = try XCTUnwrap(entry["room_id"])
      let callId = try XCTUnwrap(entry["call_id"])
      XCTAssertEqual(
        CallIdentity.uuid(roomId: roomId, callId: callId).uuidString, entry["uuid"], roomId)
    }
  }

  func testEveryOpaqueIdIsTheTruncatedHmacOfTheId() throws {
    let fixture = try fixture("opaque_ids_v1.json")
    let key = SymmetricKey(data: try bytes(fixture["install_key"]))
    let cases = try XCTUnwrap(fixture["cases"] as? [[String: String]])
    XCTAssertEqual(cases.count, 4)
    for entry in cases {
      let input = try XCTUnwrap(entry["input"])
      let mac = HMAC<SHA256>.authenticationCode(for: Array(input.utf8), using: key)
      XCTAssertEqual(String(hex(mac).prefix(32)), entry["token"], input)
    }
  }

  func testTheSealedRoomFileOpensOnlyUnderItsOwnName() throws {
    let fixture = try fixture("sealed_file_v1.json")
    let key = try bytes(fixture["rm_key"])
    let room = try XCTUnwrap((fixture["cases"] as? [[String: String]])?.first)
    let name = try XCTUnwrap(room["name"])
    let opened = try openFile(try bytes(room["sealed"]), name: name, key: key)
    XCTAssertEqual(String(decoding: opened, as: UTF8.self), room["plaintext"])
    let tampered = try XCTUnwrap(fixture["tamper"] as? [[String: String]])
    XCTAssertEqual(tampered.count, 5)
    for tamper in tampered {
      XCTAssertThrowsError(
        try openFile(
          try bytes(tamper["sealed"]), name: try XCTUnwrap(tamper["file_name"]), key: key),
        tamper["name"] ?? "")
    }
  }
}
