import CryptoKit
import XCTest

@testable import Runner

final class VoipBlobTests: XCTestCase {
  private let header = VoipBlobHeader(kid: VoipBlobFixture.kid, expiry: VoipBlobFixture.expiry)

  private func keys(_ kid: UInt32) -> SymmetricKey? {
    kid == VoipBlobFixture.kid ? VoipBlobFixture.key : nil
  }

  private func contract() throws -> (fixture: [String: Any], key: SymmetricKey, kid: UInt32) {
    let fixture = try ContractFixture.load("voip_blob_v1.json")
    let key = SymmetricKey(data: try ContractFixture.bytes(fixture["key"]))
    let kid = UInt32(try XCTUnwrap(fixture["kid"] as? Int))
    return (fixture, key, kid)
  }

  func testEveryContractVectorOpensToItsPayload() throws {
    let (fixture, key, kid) = try contract()
    let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
    XCTAssertTrue(
      Set(vectors.compactMap { $0["name"] as? String }).isSuperset(of: [
        "known_answer", "long_ids", "escaped_text", "skewed_sender",
      ]))
    for vector in vectors {
      let name = vector["name"] as? String ?? "?"
      let payload = try XCTUnwrap(vector["payload"] as? [String: Any], name)
      let expected = VoipRing(
        room: try XCTUnwrap(payload["room"] as? String, name),
        call: try XCTUnwrap(payload["call"] as? String, name),
        caller: try XCTUnwrap(payload["caller"] as? String, name),
        cname: try XCTUnwrap(payload["cname"] as? String, name),
        rname: try XCTUnwrap(payload["rname"] as? String, name),
        kind: try XCTUnwrap(VoipKind(rawValue: payload["kind"] as? String ?? ""), name),
        ts: try XCTUnwrap((payload["ts"] as? NSNumber)?.int64Value, name),
        rts: try XCTUnwrap((payload["rts"] as? NSNumber)?.int64Value, name))
      let expiry = UInt32(try XCTUnwrap(vector["x"] as? Int, name))
      let blob = try ContractFixture.bytes(vector["blob"])

      XCTAssertEqual(
        VoipBlob.open(blob, key: { $0 == kid ? key : nil }),
        .opened(VoipBlobHeader(kid: kid, expiry: expiry), expected), name)
    }
  }

  func testEveryContractTamperCaseHasItsOutcome() throws {
    let (fixture, key, kid) = try contract()
    let tampered = try XCTUnwrap(fixture["tamper"] as? [[String: Any]])
    XCTAssertTrue(
      Set(tampered.compactMap { $0["name"] as? String }).isSuperset(of: [
        "flipped_tag", "flipped_aad_byte", "flipped_ciphertext_byte", "truncated",
        "short_header", "unpadded_length", "not_base64", "unknown_version", "unknown_kid",
      ]))
    for tamper in tampered {
      let name = tamper["name"] as? String ?? "?"
      let outcome = VoipBlob.open(
        payload: ["z": tamper["blob"] as? String ?? "", "event_id": "$z"],
        key: { $0 == kid ? key : nil })
      switch (tamper["expect"] as? String, outcome) {
      case ("forged", .forged), ("generic", .unknownKid), ("generic", .unknownVersion):
        continue
      default:
        XCTFail("\(name) expected \(tamper["expect"] ?? "?") but opened as \(outcome)")
      }
    }
  }

  func testTheFixtureSealerReproducesTheContractBlob() throws {
    let (fixture, _, _) = try contract()
    let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
    let known = try XCTUnwrap(vectors.first { $0["name"] as? String == "known_answer" })

    XCTAssertEqual(VoipBlobFixture.seal(), try ContractFixture.bytes(known["blob"]))
    XCTAssertEqual(
      VoipBlobFixture.hex(SHA256.hash(data: VoipBlobFixture.seal())), VoipBlobFixture.digest)
  }

  func testTheHeaderIsReadableWithoutAKey() {
    XCTAssertEqual(VoipBlob.header(VoipBlobFixture.seal()), header)
  }

  func testACiphertextOfAnyOtherSizeIsForged() {
    XCTAssertEqual(
      VoipBlob.open(VoipBlobFixture.seal(padTo: 600), key: keys), .forged(header))
    XCTAssertEqual(
      VoipBlob.open(VoipBlobFixture.seal().prefix(30), key: keys), .forged(header))
  }

  func testABlobTooShortForItsHeaderIsForgedWhateverItsVersion() {
    XCTAssertEqual(VoipBlob.open(VoipBlobFixture.seal().prefix(5), key: keys), .forged(nil))
    XCTAssertEqual(VoipBlob.open(Data([0x02, 0x00]), key: keys), .forged(nil))
    XCTAssertEqual(VoipBlob.open(Data(), key: keys), .forged(nil))
  }

  func testAnUnknownKidIsGenericWhateverItsLength() {
    XCTAssertEqual(
      VoipBlob.open(VoipBlobFixture.seal().prefix(30), key: { _ in nil }), .unknownKid(header))
  }

  func testAnAuthenticRingWithoutItsRoomIsForged() {
    let blob = VoipBlobFixture.seal(
      #"{"room":"","call":"c1","caller":"@a:zuno.im","cname":"","rname":"","kind":"voice","ts":1,"rts":1}"#
    )

    XCTAssertEqual(VoipBlob.open(blob, key: keys), .forged(header))
  }

  func testTheCanaryOpensWithoutARoom() {
    let blob = VoipBlobFixture.seal(
      #"{"room":"","call":"canary-1790000000000","caller":"@zuno-push:zuno.im","cname":"","rname":"","kind":"canary","ts":1790000000000,"rts":1790000000000}"#
    )

    guard case .opened(_, let ring) = VoipBlob.open(blob, key: keys) else {
      return XCTFail("the canary did not open")
    }
    XCTAssertEqual(ring.kind, .canary)
    XCTAssertEqual(ring.room, "")
  }

  func testAnUnknownKindIsForged() {
    let blob = VoipBlobFixture.seal(
      #"{"room":"!r:zuno.im","call":"c1","caller":"@a:zuno.im","cname":"","rname":"","kind":"fax","ts":1,"rts":1}"#
    )

    XCTAssertEqual(VoipBlob.open(blob, key: keys), .forged(header))
  }

  func testThePushCarriesTheBlobInZ() {
    let blob = VoipBlobFixture.seal()

    XCTAssertEqual(VoipBlob.data(from: ["z": blob.base64EncodedString(), "event_id": "$z"]), blob)
    XCTAssertNil(VoipBlob.data(from: ["z": "%%%"]))
    XCTAssertNil(VoipBlob.data(from: ["event_id": "$z"]))
    XCTAssertEqual(VoipBlob.open(payload: ["event_id": "$z"], key: keys), .forged(nil))
    XCTAssertEqual(VoipBlob.open(payload: ["z": "%%%"], key: keys), .forged(nil))
  }
}
