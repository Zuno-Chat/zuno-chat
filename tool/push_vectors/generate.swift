import CryptoKit
import Foundation

func byteRange(_ first: UInt8, _ last: UInt8) -> [UInt8] {
  Array(first...last)
}

func bigEndian(_ value: UInt32) -> [UInt8] {
  [
    UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF),
    UInt8(value & 0xFF),
  ]
}

func hex(_ bytes: some Sequence<UInt8>) -> String {
  bytes.map { String(format: "%02x", $0) }.joined()
}

func base64(_ bytes: [UInt8]) -> String {
  Data(bytes).base64EncodedString()
}

func flipped(_ bytes: [UInt8], at index: Int) -> [UInt8] {
  var copy = bytes
  copy[index] ^= 0x01
  return copy
}

func isStripped(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
    return true
  default: return false
  }
}

func normalizedName(_ name: String) -> String {
  var kept = String.UnicodeScalarView()
  var used = 0
  for scalar in name.unicodeScalars where !isStripped(scalar) {
    let size = String(scalar).utf8.count
    guard used + size <= 64 else { break }
    used += size
    kept.append(scalar)
  }
  return String(kept)
}

func jsonString(_ value: String) -> String {
  var out = "\""
  for scalar in value.unicodeScalars {
    switch scalar {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    case "\u{08}": out += "\\b"
    case "\u{0C}": out += "\\f"
    case let control where control.value < 0x20:
      out += String(format: "\\u%04x", control.value)
    default: out.unicodeScalars.append(scalar)
    }
  }
  return out + "\""
}

struct Ring {
  let room: String
  let call: String
  let caller: String
  let cname: String
  let rname: String
  let kind: String
  let ts: Int64
  let rts: Int64

  var plaintext: String {
    let fields = [
      ("room", jsonString(room)), ("call", jsonString(call)), ("caller", jsonString(caller)),
      ("cname", jsonString(normalizedName(cname))), ("rname", jsonString(normalizedName(rname))),
      ("kind", jsonString(kind)), ("ts", String(ts)), ("rts", String(rts)),
    ]
    return "{" + fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
  }

  var expiry: UInt32 {
    UInt32(min(ts, rts + 30_000) / 1000 + 45)
  }
}

let voipKey = byteRange(0x00, 0x1F)
let voipKid: UInt32 = 16_909_060
let voipAadPrefix = "zuno-voip-v1"

func seal(_ plaintext: String, x: UInt32, nonce: [UInt8], padTo padded: Int) throws -> [UInt8] {
  let json = Array(plaintext.utf8)
  let body = json + [UInt8](repeating: 0, count: padded - json.count)
  let header = [0x01] + bigEndian(voipKid) + bigEndian(x)
  let sealed = try ChaChaPoly.seal(
    body, using: SymmetricKey(data: voipKey), nonce: ChaChaPoly.Nonce(data: nonce),
    authenticating: Array(voipAadPrefix.utf8) + header)
  return header + nonce + Array(sealed.ciphertext) + Array(sealed.tag)
}

func voipVector(name: String, ring: Ring, nonce: [UInt8]) throws -> (
  json: [String: Any], blob: [UInt8]
) {
  let plaintext = ring.plaintext
  let padded = plaintext.utf8.count > 512 ? 1024 : 512
  let blob = try seal(plaintext, x: ring.expiry, nonce: nonce, padTo: padded)
  let payload = try JSONSerialization.jsonObject(with: Data(plaintext.utf8))
  return (
    [
      "name": name,
      "x": Int(ring.expiry),
      "nonce": base64(nonce),
      "plaintext": plaintext,
      "payload": payload,
      "padded_length": padded,
      "blob": base64(blob),
      "blob_length": blob.count,
      "blob_sha256": hex(SHA256.hash(data: blob)),
    ], blob
  )
}

func voipFixture() throws -> [String: Any] {
  let knownRing = Ring(
    room: "!abc:zuno.im", call: "c1", caller: "@alice:zuno.im", cname: "Alice", rname: "",
    kind: "video", ts: 1_790_000_000_000, rts: 1_789_999_999_000)
  let known = try voipVector(name: "known_answer", ring: knownRing, nonce: byteRange(0xA0, 0xAB))
  let long = try voipVector(
    name: "long_ids",
    ring: Ring(
      room: "!" + String(repeating: "r", count: 400) + ":zuno.im", call: "c2",
      caller: "@zoe:zuno.im", cname: "Zoë 李𝓩", rname: "Design team", kind: "voice",
      ts: 1_790_000_055_000, rts: 1_790_000_054_000),
    nonce: byteRange(0xC0, 0xCB))
  let escaped = try voipVector(
    name: "escaped_text",
    ring: Ring(
      room: "!esc:zuno.im", call: "c3\t\u{01}", caller: "@al:zuno.im", cname: #"Al "Bo" \ C/D"#,
      rname: "R&D / Ops", kind: "video", ts: 1_790_000_200_000, rts: 1_790_000_199_500),
    nonce: byteRange(0xD0, 0xDB))
  let skewed = try voipVector(
    name: "skewed_sender",
    ring: Ring(
      room: "!skew:zuno.im", call: "c4", caller: "@sam:zuno.im", cname: "Sam", rname: "",
      kind: "voice", ts: 1_790_000_300_250, rts: 1_790_000_100_500),
    nonce: byteRange(0xE0, 0xEB))
  var unknownKid = known.blob
  unknownKid.replaceSubrange(1..<5, with: bigEndian(voipKid + 1))
  var unknownVersion = known.blob
  unknownVersion[0] = 0x02
  let unpadded = try seal(
    knownRing.plaintext, x: knownRing.expiry, nonce: byteRange(0xA0, 0xAB), padTo: 600)
  let tamper: [(String, String, String)] = [
    ("flipped_tag", base64(flipped(known.blob, at: known.blob.count - 1)), "forged"),
    ("flipped_aad_byte", base64(flipped(known.blob, at: 8)), "forged"),
    ("flipped_ciphertext_byte", base64(flipped(known.blob, at: 21)), "forged"),
    ("truncated", base64(Array(known.blob.dropLast())), "forged"),
    ("short_header", base64(Array(known.blob.prefix(8))), "forged"),
    ("unpadded_length", base64(unpadded), "forged"),
    ("not_base64", "*" + base64(known.blob).dropFirst(), "forged"),
    ("unknown_version", base64(unknownVersion), "generic"),
    ("unknown_kid", base64(unknownKid), "generic"),
  ]
  return [
    "aad_prefix": voipAadPrefix,
    "key": base64(voipKey),
    "kid": Int(voipKid),
    "vectors": [known.json, long.json, escaped.json, skewed.json],
    "tamper": tamper.map {
      ["name": $0.0, "of": "known_answer", "blob": $0.1, "expect": $0.2]
    },
  ]
}

func namesFixture() -> [String: Any] {
  let cases: [(String, String)] = [
    ("ascii_short", "Alice"),
    ("ascii_exactly_64", String(repeating: "a", count: 64)),
    ("ascii_over_64", String(repeating: "abcdefghij", count: 7)),
    ("two_byte_straddles_64", String(repeating: "a", count: 63) + "é"),
    ("three_byte_straddles_64", String(repeating: "a", count: 62) + "李x"),
    ("astral_straddles_64", String(repeating: "a", count: 61) + "𝓩"),
    ("emoji_only", String(repeating: "😀", count: 20)),
    ("emoji_modifier_split", String(repeating: "a", count: 58) + "👍🏽"),
    ("controls_stripped", "Al\u{00}ice\n\tSmith\u{7F}\u{85}"),
    ("delete_stripped", "Ann\u{7F}a"),
    ("c1_control_stripped", "Bob\u{85}by"),
    ("bidi_stripped", "\u{202E}evil\u{202C} \u{200F}name\u{2066}x\u{2069}\u{200E}"),
    ("arabic_letter_mark_stripped", "Ana\u{061C}is"),
    (
      "strip_before_cut", String(repeating: "\u{01}", count: 10) + String(repeating: "a", count: 60)
    ),
    ("joiners_kept", "a\u{200D}b\u{200C}c\u{FEFF}d"),
    ("no_break_space_kept", "a\u{00A0}b"),
    ("just_below_isolates_kept", "a\u{2065}b"),
    ("just_above_isolates_kept", "a\u{206A}b"),
    ("right_to_left_text_kept", "مرحبا بك"),
    ("only_controls", "\u{202E}\u{00}\u{9F}"),
    ("empty", ""),
  ]
  return [
    "cases": cases.map { ["name": $0.0, "input": $0.1, "output": normalizedName($0.1)] }
  ]
}

let callUuidNamespace = "5C2B7E0A-3D4F-4B8E-9A61-2F7C8D0E1B34"

func callUuid(roomId: String, callId: String) -> String {
  let namespace = UUID(uuidString: callUuidNamespace)!
  var name = withUnsafeBytes(of: namespace.uuid) { Array($0) }
  name.append(contentsOf: "\(roomId)\n\(callId)".utf8)
  var hash = Array(Insecure.SHA1.hash(data: name).prefix(16))
  hash[6] = (hash[6] & 0x0F) | 0x50
  hash[8] = (hash[8] & 0x3F) | 0x80
  return UUID(
    uuid: (
      hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
      hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
    )
  ).uuidString
}

func uuidFixture() -> [String: Any] {
  let cases = [
    ("!abc:zuno.im", "c1"),
    ("!room:example.org", "call-1"),
    ("!room:example.org", ""),
    ("!caf\u{E9}:example.org", ""),
  ]
  return [
    "namespace": callUuidNamespace,
    "separator": "\n",
    "cases": cases.map {
      ["room_id": $0.0, "call_id": $0.1, "uuid": callUuid(roomId: $0.0, callId: $0.1)]
    },
  ]
}

func opaqueIdsFixture() -> [String: Any] {
  let installKey = byteRange(0x20, 0x3F)
  let cases = [
    ("room", "!abc:zuno.im"),
    ("event", "$ev1:zuno.im"),
    ("room", "!caf\u{E9}:zuno.im"),
    ("event", "$Zk3qY9_long-event.id:zuno.im"),
  ]
  return [
    "install_key": base64(installKey),
    "length": 32,
    "cases": cases.map { kind, input in
      [
        "kind": kind, "input": input,
        "token": String(
          hex(
            HMAC<SHA256>.authenticationCode(
              for: Array(input.utf8), using: SymmetricKey(data: installKey))
          ).prefix(32)),
      ]
    },
  ]
}

func sealedFileFixture() throws -> [String: Any] {
  let rmKey = byteRange(0x40, 0x5F)
  let nonce = byteRange(0xB0, 0xBB)
  let name = "rooms/2d2de6b6c6565ad95bf365845db19da9"
  let plaintext = #"{"v":1,"room":"!abc:zuno.im","title":"Alice","dm":true,"partner":"Alice"}"#
  let sealed = try ChaChaPoly.seal(
    Array(plaintext.utf8), using: SymmetricKey(data: rmKey), nonce: ChaChaPoly.Nonce(data: nonce),
    authenticating: Array(name.utf8) + [0x01])
  let file = [0x01] + nonce + Array(sealed.ciphertext) + Array(sealed.tag)
  var unknownVersion = file
  unknownVersion[0] = 0x02
  let tamper: [(String, String, [UInt8])] = [
    ("wrong_name", "rooms/00000000000000000000000000000000", file),
    ("flipped_tag", name, flipped(file, at: file.count - 1)),
    ("flipped_ciphertext_byte", name, flipped(file, at: 13)),
    ("unknown_version", name, unknownVersion),
    ("truncated", name, Array(file.prefix(28))),
  ]
  return [
    "rm_key": base64(rmKey),
    "version": 1,
    "cases": [
      ["name": name, "nonce": base64(nonce), "plaintext": plaintext, "sealed": base64(file)]
    ],
    "tamper": tamper.map {
      ["name": $0.0, "file_name": $0.1, "sealed": base64($0.2), "expect": "fail"]
    },
  ]
}

func write(_ object: [String: Any], to directory: URL, name: String) throws {
  let data = try JSONSerialization.data(
    withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  var text = ""
  for scalar in String(decoding: data, as: UTF8.self).unicodeScalars {
    if scalar.value < 0x7F {
      text.unicodeScalars.append(scalar)
    } else {
      for unit in String(scalar).utf16 { text += String(format: "\\u%04x", unit) }
    }
  }
  try Data((text + "\n").utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: swift generate.swift <output directory>\n".utf8))
  exit(64)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try write(voipFixture(), to: output, name: "voip_blob_v1.json")
try write(namesFixture(), to: output, name: "names_v1.json")
try write(uuidFixture(), to: output, name: "call_uuid_v5.json")
try write(opaqueIdsFixture(), to: output, name: "opaque_ids_v1.json")
try write(sealedFileFixture(), to: output, name: "sealed_file_v1.json")
