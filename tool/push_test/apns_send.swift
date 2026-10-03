import CryptoKit
import Foundation

struct ToolError: Error, CustomStringConvertible {
  let description: String
}

enum Command: String {
  case alert, voip, seal, selftest

  private static let sendOptions = ["p8", "key-id", "token", "team-id", "topic"]
  private static let sealOptions = [
    "key", "kid", "room", "call", "caller", "cname", "rname", "kind", "nonce", "ts", "rts",
  ]

  var valueOptions: [String] {
    switch self {
    case .alert: Command.sendOptions + ["room-id", "event-id", "unread"]
    case .voip: Command.sendOptions + Command.sealOptions
    case .seal: Command.sealOptions
    case .selftest: []
    }
  }

  var flagOptions: [String] {
    switch self {
    case .alert: ["no-sound", "production"]
    case .voip: ["production"]
    case .seal, .selftest: []
    }
  }

  var accepted: String {
    let names = (valueOptions + flagOptions).map { "--\($0)" }
    return names.isEmpty ? "no options" : names.joined(separator: " ")
  }
}

struct Options {
  private var values: [String: String] = [:]
  private var flags: Set<String> = []

  init(_ arguments: ArraySlice<String>, for command: Command) throws {
    var remaining = arguments[...]
    while let argument = remaining.popFirst() {
      guard Options.isOption(argument) else {
        throw ToolError(description: "unexpected argument \(argument)")
      }
      let bytes = argument.utf8.dropFirst(2)
      let equals = bytes.firstIndex(of: UInt8(ascii: "="))
      let name = String(decoding: bytes[..<(equals ?? bytes.endIndex)], as: UTF8.self)
      let attached = equals.map {
        String(decoding: bytes[bytes.index(after: $0)...], as: UTF8.self)
      }
      if command.flagOptions.contains(name) {
        guard attached == nil else { throw ToolError(description: "--\(name) takes no value") }
        flags.insert(name)
        continue
      }
      guard command.valueOptions.contains(name) else {
        throw ToolError(
          description: "unknown option --\(name); \(command.rawValue) takes \(command.accepted)")
      }
      if let attached {
        values[name] = attached
        continue
      }
      guard let value = remaining.popFirst() else {
        throw ToolError(description: "--\(name) needs a value")
      }
      guard !Options.isOption(value) else {
        throw ToolError(
          description: "--\(name) needs a value; one that starts with -- goes as --\(name)=VALUE")
      }
      values[name] = value
    }
  }

  private static func isOption(_ token: String) -> Bool { token.utf8.starts(with: "--".utf8) }

  func has(_ flag: String) -> Bool { flags.contains(flag) }

  func optional(_ name: String) -> String? { values[name] }

  func required(_ name: String) throws -> String {
    guard let value = values[name] else { throw ToolError(description: "--\(name) is required") }
    return value
  }

  func number(_ name: String, in range: ClosedRange<Int64>) throws -> Int64 {
    let text = try required(name)
    guard text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), let parsed = Int64(text),
      range.contains(parsed)
    else {
      throw ToolError(
        description:
          "--\(name) must be a whole number from \(range.lowerBound) to \(range.upperBound)")
    }
    return parsed
  }

  func optionalNumber(_ name: String, in range: ClosedRange<Int64>) throws -> Int64? {
    try values[name] == nil ? nil : number(name, in: range)
  }
}

func bigEndian(_ value: UInt32) -> [UInt8] {
  [
    UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF),
    UInt8(value & 0xFF),
  ]
}

func hexString(_ bytes: some Sequence<UInt8>) -> String {
  bytes.map { String(format: "%02x", $0) }.joined()
}

func hexBytes(_ hex: String) throws -> [UInt8] {
  let digits = Array(hex.utf8)
  guard !digits.isEmpty, digits.count % 2 == 0 else {
    throw ToolError(description: "\(hex) is not hex")
  }
  return try stride(from: 0, to: digits.count, by: 2).map { index in
    let pair = digits[index...index + 1]
    guard pair.allSatisfy({ Unicode.Scalar($0).properties.isASCIIHexDigit }),
      let byte = UInt8(String(decoding: pair, as: UTF8.self), radix: 16)
    else { throw ToolError(description: "\(hex) is not hex") }
    return byte
  }
}

func deviceToken(_ value: String) throws -> String {
  if value.count >= 64, let bytes = try? hexBytes(value) {
    return hexString(bytes)
  }
  if let data = Data(base64Encoded: value), data.count >= 32 {
    return hexString(data)
  }
  throw ToolError(description: "--token must be the hex device token or the base64 push key")
}

enum VoipSeal {
  static let aadPrefix = Array("zuno-voip-v1".utf8)

  static func jsonString(_ value: String) -> String {
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

  static func normalizedName(_ name: String) -> String {
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

  static func plaintext(
    room: String, call: String, caller: String, cname: String, rname: String, kind: String,
    ts: Int64, rts: Int64
  ) -> String {
    let fields = [
      ("room", jsonString(room)), ("call", jsonString(call)), ("caller", jsonString(caller)),
      ("cname", jsonString(normalizedName(cname))),
      ("rname", jsonString(normalizedName(rname))), ("kind", jsonString(kind)),
      ("ts", String(ts)), ("rts", String(rts)),
    ]
    return "{" + fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
  }

  static func expiry(ts: Int64, rts: Int64) throws -> UInt32 {
    let (limit, overflow) = rts.addingReportingOverflow(30_000)
    guard !overflow, let x = UInt32(exactly: min(ts, limit) / 1000 + 45) else {
      throw ToolError(description: "the expiry does not fit in 32 bits")
    }
    return x
  }

  static func seal(plaintext: String, key: [UInt8], kid: UInt32, x: UInt32, nonce: [UInt8])
    throws -> [UInt8]
  {
    let json = Array(plaintext.utf8)
    guard json.count <= 1024 else { throw ToolError(description: "the payload is over 1024 bytes") }
    guard key.count == 32 else { throw ToolError(description: "the key must be 32 bytes") }
    guard nonce.count == 12 else { throw ToolError(description: "the nonce must be 12 bytes") }
    let padded = json.count > 512 ? 1024 : 512
    let header = [0x01] + bigEndian(kid) + bigEndian(x)
    let sealed = try ChaChaPoly.seal(
      json + [UInt8](repeating: 0, count: padded - json.count), using: SymmetricKey(data: key),
      nonce: ChaChaPoly.Nonce(data: nonce), authenticating: aadPrefix + header)
    return header + nonce + Array(sealed.ciphertext) + Array(sealed.tag)
  }

  private static let times: ClosedRange<Int64> = 1...4_000_000_000_000

  static func blob(_ options: Options) throws -> [UInt8] {
    guard let key = Data(base64Encoded: try options.required("key")) else {
      throw ToolError(description: "--key is not base64")
    }
    let kid = UInt32(try options.number("kid", in: 1...4_294_967_295))
    let kind = options.optional("kind") ?? "video"
    guard ["voice", "video", "canary"].contains(kind) else {
      throw ToolError(description: "--kind must be voice, video or canary")
    }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let ts = try options.optionalNumber("ts", in: times) ?? now
    let rts = try options.optionalNumber("rts", in: times) ?? ts
    let nonce =
      try options.optional("nonce").map(hexBytes)
      ?? (0..<12).map { _ in UInt8.random(in: 0...255) }
    let text = plaintext(
      room: try options.required("room"), call: try options.required("call"),
      caller: try options.required("caller"), cname: options.optional("cname") ?? "",
      rname: options.optional("rname") ?? "", kind: kind, ts: ts, rts: rts)
    return try seal(
      plaintext: text, key: Array(key), kid: kid, x: expiry(ts: ts, rts: rts), nonce: nonce)
  }
}

enum ProviderToken {
  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  static func make(key: P256.Signing.PrivateKey, keyId: String, teamId: String, issuedAt: Int)
    throws -> String
  {
    for (name, value) in [("key id", keyId), ("team id", teamId)] {
      guard value.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
        throw ToolError(description: "the \(name) must be 10 capital letters or digits")
      }
    }
    let header = base64URL(Data(#"{"alg":"ES256","kid":"\#(keyId)"}"#.utf8))
    let claims = base64URL(Data(#"{"iss":"\#(teamId)","iat":\#(issuedAt)}"#.utf8))
    let input = "\(header).\(claims)"
    let signature = try key.signature(for: Data(input.utf8))
    return "\(input).\(base64URL(signature.rawRepresentation))"
  }
}

enum Payloads {
  static func alert(_ options: Options) throws -> [String: Any] {
    alert(
      roomId: options.optional("room-id") ?? "!zuno-push-test:zuno.im",
      eventId: options.optional("event-id") ?? "$zuno_test_1",
      unread: Int(try options.optionalNumber("unread", in: 0...2_147_483_647) ?? 1),
      sound: !options.has("no-sound"))
  }

  static func alert(roomId: String, eventId: String, unread: Int, sound: Bool) -> [String: Any] {
    var aps: [String: Any] = ["mutable-content": 1, "alert": ["body": "New message"]]
    if sound { aps["sound"] = "message_tone.caf" }
    return ["aps": aps, "room_id": roomId, "event_id": eventId, "unread_count": unread]
  }

  static func voip(blob: [UInt8]) -> [String: Any] {
    ["z": Data(blob).base64EncodedString(), "event_id": "$z"]
  }
}

enum PushType: String {
  case alert, voip

  var defaultTopic: String {
    switch self {
    case .alert: "im.zuno.chat"
    case .voip: "im.zuno.chat.voip"
    }
  }

  func payload(_ options: Options) throws -> [String: Any] {
    switch self {
    case .alert: try Payloads.alert(options)
    case .voip: Payloads.voip(blob: try VoipSeal.blob(options))
    }
  }
}

func apnsRequest(
  _ payload: [String: Any], type: PushType, deviceToken: String, providerToken: String,
  _ options: Options
) throws -> URLRequest {
  let host = options.has("production") ? "api.push.apple.com" : "api.sandbox.push.apple.com"
  guard (try? hexBytes(deviceToken)) != nil,
    let url = URL(string: "https://\(host)/3/device/\(deviceToken)")
  else { throw ToolError(description: "the device token is not hex") }
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  request.setValue("bearer \(providerToken)", forHTTPHeaderField: "authorization")
  request.setValue(
    options.optional("topic") ?? type.defaultTopic, forHTTPHeaderField: "apns-topic")
  request.setValue(type.rawValue, forHTTPHeaderField: "apns-push-type")
  request.setValue("10", forHTTPHeaderField: "apns-priority")
  return request
}

func send(_ type: PushType, _ options: Options) async throws {
  let payload = try type.payload(options)
  let token = try deviceToken(try options.required("token"))
  let pem = try String(contentsOfFile: try options.required("p8"), encoding: .utf8)
  let providerToken = try ProviderToken.make(
    key: P256.Signing.PrivateKey(pemRepresentation: pem), keyId: try options.required("key-id"),
    teamId: options.optional("team-id") ?? "5V9UP3J9CK",
    issuedAt: Int(Date().timeIntervalSince1970))
  let request = try apnsRequest(
    payload, type: type, deviceToken: token, providerToken: providerToken, options)
  let (data, response) = try await URLSession.shared.data(for: request)
  let http = response as? HTTPURLResponse
  let status = http?.statusCode ?? 0
  let apnsId = http?.value(forHTTPHeaderField: "apns-id") ?? "-"
  let host = request.url?.host ?? "-"
  let line = "\(host) \(status) apns-id \(apnsId) \(String(decoding: data, as: UTF8.self))"
  guard status == 200 else { throw ToolError(description: line) }
  print(line)
}

func check(_ condition: Bool, _ message: String) throws {
  guard condition else { throw ToolError(description: "selftest: \(message)") }
}

func thrownMessage(_ action: () throws -> Void) -> String {
  do {
    try action()
    return ""
  } catch {
    return "\(error)"
  }
}

func tokenParts(_ token: String) -> [String]? {
  let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
  let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
  guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(alphabet.contains) })
  else { return nil }
  return parts
}

func decodedBase64URL(_ part: String) -> Data {
  var base64 = part.replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
  return Data(base64Encoded: base64) ?? Data()
}

func selftest() throws {
  let contract = try VoipSeal.seal(
    plaintext: VoipSeal.plaintext(
      room: "!abc:zuno.im", call: "c1", caller: "@alice:zuno.im", cname: "Alice", rname: "",
      kind: "video", ts: 1_790_000_000_000, rts: 1_789_999_999_000),
    key: Array(0x00...0x1F), kid: 16_909_060,
    x: VoipSeal.expiry(ts: 1_790_000_000_000, rts: 1_789_999_999_000),
    nonce: Array(0xA0...0xAB))
  try check(contract.count == 549, "the contract blob is not 549 bytes")
  try check(
    hexString(SHA256.hash(data: contract))
      == "aaf898f4941c4ff73dd0b30839264042535a098823be3a5ed024339fc58b6a80",
    "the contract blob does not match its SHA-256")

  let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("test/fixtures/push/voip_blob_v1.json")
  let fixture =
    try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any] ?? [:]
  let key = Array(Data(base64Encoded: fixture["key"] as? String ?? "") ?? Data())
  let kid = UInt32(fixture["kid"] as? Int ?? 0)
  let vectors = fixture["vectors"] as? [[String: Any]] ?? []
  try check(!vectors.isEmpty, "the fixture holds no vectors")
  for vector in vectors {
    let payload = vector["payload"] as? [String: Any] ?? [:]
    let ts = Int64(payload["ts"] as? Int ?? 0)
    let rts = Int64(payload["rts"] as? Int ?? 0)
    try check(
      Int(VoipSeal.expiry(ts: ts, rts: rts)) == vector["x"] as? Int,
      "vector \(vector["name"] ?? "?") has another expiry")
    let blob = try VoipSeal.seal(
      plaintext: VoipSeal.plaintext(
        room: payload["room"] as? String ?? "", call: payload["call"] as? String ?? "",
        caller: payload["caller"] as? String ?? "", cname: payload["cname"] as? String ?? "",
        rname: payload["rname"] as? String ?? "", kind: payload["kind"] as? String ?? "",
        ts: ts, rts: rts),
      key: key, kid: kid, x: VoipSeal.expiry(ts: ts, rts: rts),
      nonce: Array(Data(base64Encoded: vector["nonce"] as? String ?? "") ?? Data()))
    try check(
      Data(blob).base64EncodedString() == vector["blob"] as? String,
      "vector \(vector["name"] ?? "?") does not match the fixture")
  }

  let signingKey = P256.Signing.PrivateKey()
  let reloaded = try P256.Signing.PrivateKey(pemRepresentation: signingKey.pemRepresentation)
  let jwt = try ProviderToken.make(
    key: reloaded, keyId: "ABC123DEFG", teamId: "5V9UP3J9CK", issuedAt: 1_790_000_000)
  let parts = tokenParts(jwt) ?? []
  try check(parts.count == 3, "the provider token is not three base64url parts without padding")
  let malformed = [
    "a.b.c.", "a.b.c..", "a..c", "a.b..c", ".b.c", "a.b.", "a.b", "a.b.c.d", "", "a.b.c=", "a.b.c+",
    "a.b/c.d", "a b.c.d",
  ]
  for token in malformed {
    try check(tokenParts(token) == nil, "\(token.debugDescription) is accepted as a provider token")
  }
  try check(tokenParts("a.b.c") != nil, "a plain three-part token is refused")
  try check(
    String(decoding: decodedBase64URL(parts[0]), as: UTF8.self)
      == #"{"alg":"ES256","kid":"ABC123DEFG"}"#,
    "the provider token header is wrong")
  try check(
    String(decoding: decodedBase64URL(parts[1]), as: UTF8.self)
      == #"{"iss":"5V9UP3J9CK","iat":1790000000}"#,
    "the provider token claims are wrong")
  try check(
    signingKey.publicKey.isValidSignature(
      try P256.Signing.ECDSASignature(rawRepresentation: decodedBase64URL(parts[2])),
      for: Data("\(parts[0]).\(parts[1])".utf8)),
    "the provider token signature does not verify")

  let alert = Payloads.alert(roomId: "!r:zuno.im", eventId: "$e", unread: 2, sound: true)
  try check(
    NSDictionary(dictionary: alert).isEqual(to: [
      "aps": ["mutable-content": 1, "alert": ["body": "New message"], "sound": "message_tone.caf"],
      "room_id": "!r:zuno.im", "event_id": "$e", "unread_count": 2,
    ]), "the alert payload is not what Sygnal sends")
  let quiet = Payloads.alert(roomId: "!r:zuno.im", eventId: "$e", unread: 2, sound: false)
  try check((quiet["aps"] as? [String: Any])?["sound"] == nil, "a quiet alert has a sound")
  try check(
    NSDictionary(dictionary: Payloads.voip(blob: [1, 2, 3])).isEqual(to: [
      "z": "AQID", "event_id": "$z",
    ]), "the VoIP payload is wrong")

  try check(
    try deviceToken("obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=")
      == String(
        repeating: "a1b2c3d4", count: 8), "a base64 push key does not become the device token")
  try check(
    try deviceToken(String(repeating: "A1B2C3D4", count: 8))
      == String(
        repeating: "a1b2c3d4", count: 8), "a hex device token is not kept")
  try check((try? deviceToken("zz")) == nil, "a token that is neither hex nor base64 is accepted")

  let namesURL = fixtureURL.deletingLastPathComponent().appendingPathComponent("names_v1.json")
  let names =
    try JSONSerialization.jsonObject(with: Data(contentsOf: namesURL)) as? [String: Any] ?? [:]
  let cases = names["cases"] as? [[String: String]] ?? []
  try check(!cases.isEmpty, "the names fixture holds no cases")
  for entry in cases {
    try check(
      VoipSeal.normalizedName(entry["input"] ?? "") == entry["output"],
      "name \(entry["name"] ?? "?") does not match the fixture")
  }
  try check(
    VoipSeal.jsonString("a\"b\\c/\nd\u{01}é") == #""a\"b\\c/\nd\u0001é""#,
    "JSON strings are escaped wrongly")
  try requestChecks(contract: contract)
  try inputChecks()
  print("selftest: ok")
}

func requestChecks(contract: [UInt8]) throws {
  let device = String(repeating: "a1b2c3d4", count: 8)
  let sandbox = "https://api.sandbox.push.apple.com/3/device/\(device)"
  let production = "https://api.push.apple.com/3/device/\(device)"
  let bearer = "bearer PROVIDER.TOKEN"
  let voipLine = [
    "--key", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "--kid", "16909060", "--room",
    "!abc:zuno.im", "--call", "c1", "--caller", "@alice:zuno.im", "--cname", "Alice", "--rname", "",
    "--kind", "video", "--nonce", "a0a1a2a3a4a5a6a7a8a9aaab", "--ts", "1790000000000", "--rts",
    "1789999999000",
  ]

  func alertRequest(_ arguments: [String], to token: String? = nil) throws -> URLRequest {
    let options = try Options(arguments[...], for: .alert)
    return try apnsRequest(
      PushType.alert.payload(options), type: .alert, deviceToken: token ?? device,
      providerToken: "PROVIDER.TOKEN", options)
  }

  func voipRequest(_ arguments: [String]) throws -> URLRequest {
    let options = try Options((voipLine + arguments)[...], for: .voip)
    return try apnsRequest(
      PushType.voip.payload(options), type: .voip, deviceToken: device,
      providerToken: "PROVIDER.TOKEN", options)
  }

  func shape(_ request: URLRequest) -> [String] {
    [
      request.url?.absoluteString ?? "", request.httpMethod ?? "",
      request.value(forHTTPHeaderField: "authorization") ?? "",
      request.value(forHTTPHeaderField: "apns-topic") ?? "",
      request.value(forHTTPHeaderField: "apns-push-type") ?? "",
      request.value(forHTTPHeaderField: "apns-priority") ?? "",
      String(request.allHTTPHeaderFields?.count ?? 0),
    ]
  }

  func body(_ request: URLRequest) -> NSDictionary {
    let parsed = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    return NSDictionary(dictionary: parsed as? [String: Any] ?? [:])
  }

  let alert = try alertRequest([])
  try check(
    shape(alert) == [sandbox, "POST", bearer, "im.zuno.chat", "alert", "10", "4"],
    "the sandbox alert request is wrong: \(shape(alert))")
  try check(
    body(alert).isEqual(to: [
      "aps": ["mutable-content": 1, "alert": ["body": "New message"], "sound": "message_tone.caf"],
      "room_id": "!zuno-push-test:zuno.im", "event_id": "$zuno_test_1", "unread_count": 1,
    ]), "the alert body is wrong")

  let quiet = try alertRequest([
    "--production", "--no-sound", "--unread", "7", "--room-id", "!r:zuno.im", "--event-id", "$e",
  ])
  try check(
    shape(quiet) == [production, "POST", bearer, "im.zuno.chat", "alert", "10", "4"],
    "the production alert request is wrong: \(shape(quiet))")
  try check(
    body(quiet).isEqual(to: [
      "aps": ["mutable-content": 1, "alert": ["body": "New message"]],
      "room_id": "!r:zuno.im", "event_id": "$e", "unread_count": 7,
    ]), "the quiet alert body is wrong")

  let topic = try alertRequest(["--topic", "im.zuno.chat.test"])
  try check(
    shape(topic) == [sandbox, "POST", bearer, "im.zuno.chat.test", "alert", "10", "4"],
    "an explicit --topic is not used: \(shape(topic))")

  let pushKey = try deviceToken("obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=")
  try check(
    try alertRequest([], to: pushKey).url?.absoluteString == sandbox,
    "a base64 push key does not reach the URL as hex")

  let ringBody: [String: Any] = ["z": Data(contract).base64EncodedString(), "event_id": "$z"]
  let ring = try voipRequest([])
  try check(
    shape(ring) == [sandbox, "POST", bearer, "im.zuno.chat.voip", "voip", "10", "4"],
    "the sandbox VoIP request is wrong: \(shape(ring))")
  try check(body(ring).isEqual(to: ringBody), "the VoIP body is not the contract blob")

  let liveRing = try voipRequest(["--production", "--topic", "im.zuno.chat.voip.test"])
  try check(
    shape(liveRing) == [production, "POST", bearer, "im.zuno.chat.voip.test", "voip", "10", "4"],
    "the production VoIP request is wrong: \(shape(liveRing))")
  try check(body(liveRing).isEqual(to: ringBody), "the production VoIP body is wrong")

  let none = try Options([][...], for: .alert)
  for token in ["", "a b", "zz", "abc", "a1b2/../x", "a1b2c3d4?x=1", "a1b2#c3"] {
    try check(
      thrownMessage {
        _ = try apnsRequest([:], type: .alert, deviceToken: token, providerToken: "p", none)
      }.contains("the device token is not hex"),
      "\(token.debugDescription) is accepted as a device token in a request")
  }
}

func inputChecks() throws {
  let refused: [(Command, [String], String)] = [
    (.seal, ["--cnam", "Alice"], "unknown option --cnam; seal takes --key --kid"),
    (.seal, ["--production"], "unknown option --production"),
    (.alert, ["--cname", "Alice"], "unknown option --cname"),
    (.voip, ["--no-sound"], "unknown option --no-sound"),
    (.selftest, ["--room", "x"], "unknown option --room; selftest takes no options"),
    (.alert, ["--no-sond", "--production"], "unknown option --no-sond"),
    (.seal, ["--cname"], "--cname needs a value"),
    (.seal, ["--cname", "--rname", "Bob"], "--cname needs a value"),
    (.seal, ["--cname", "--weird"], "goes as --cname=VALUE"),
    (.seal, ["--cname", "--\u{200D}x"], "goes as --cname=VALUE"),
    (.seal, ["--cnam=Alice"], "unknown option --cnam; seal takes"),
    (.alert, ["--no-sound=1"], "--no-sound takes no value"),
    (.seal, ["--"], "unknown option --; seal takes"),
    (.seal, ["--=x"], "unknown option --; seal takes"),
    (.alert, ["--unread", "--no-sound"], "--unread needs a value"),
    (.seal, ["stray"], "unexpected argument stray"),
  ]
  for (command, arguments, message) in refused {
    try check(
      thrownMessage { _ = try Options(arguments[...], for: command) }.contains(message),
      "\(command.rawValue) \(arguments) is not refused with \(message)")
  }
  try check(
    thrownMessage { _ = try Options(["--cname", "Alice", "--rname", ""][...], for: .seal) }.isEmpty,
    "a valid seal command line is refused")
  try check(
    thrownMessage {
      _ = try Options(["--unread", "3", "--no-sound", "--production"][...], for: .alert)
    }.isEmpty, "a valid alert command line is refused")
  let attached = try Options(["--cname=--weird", "--rname=", "--key=AAEC="][...], for: .seal)
  try check(
    attached.optional("cname") == "--weird" && attached.optional("rname") == ""
      && attached.optional("key") == "AAEC=", "--name=value is not read")
  for mark in ["\u{200D}x", "\u{200C}", "\u{301}", "\u{1F3FD}", "\u{FE0F}"] {
    let marked = try Options(["--cname=\(mark)"][...], for: .seal)
    try check(
      marked.optional("cname")?.unicodeScalars.elementsEqual(mark.unicodeScalars) == true,
      "--cname=\(mark.debugDescription) is not read exactly")
  }

  let notNumbers = [
    "abc", "12abc", "-1", "+1", "", " 1", "1.5", "\u{FF11}\u{FF12}", "99999999999999999999",
  ]
  for text in notNumbers {
    try check(
      thrownMessage { _ = try Payloads.alert(Options(["--unread", text][...], for: .alert)) }
        .contains("--unread must be a whole number"),
      "--unread \(text.debugDescription) is accepted")
  }
  let unreadCounts: [([String], Int)] = [
    ([], 1), (["--unread", "0"], 0), (["--unread", "42"], 42),
  ]
  for (arguments, expected) in unreadCounts {
    let payload = try Payloads.alert(Options(arguments[...], for: .alert))
    try check(
      payload["unread_count"] as? Int == expected, "\(arguments) does not give \(expected) unread")
  }

  let sealLine = [
    "--key", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "--room", "!r:zuno.im", "--call", "c",
    "--caller", "@a:zuno.im",
  ]
  let sealCases: [([String], String)] = [
    (["--kid", "7"], ""),
    (["--kid", "7", "--ts", "4000000000000", "--rts", "4000000000000"], ""),
    (
      ["--kid", "7", "--ts", "4000000000001"], "--ts must be a whole number from 1 to 4000000000000"
    ),
    (
      ["--kid", "7", "--rts", "4000000000001"],
      "--rts must be a whole number from 1 to 4000000000000"
    ),
    (["--kid", "7", "--ts", "1790000000000000"], "--ts must be"),
    (["--kid", "7", "--ts", "9223372036854775807"], "--ts must be"),
    (["--kid", "7", "--ts", "0"], "--ts must be"),
    (["--kid", "7", "--ts", "-5"], "--ts must be"),
    (["--kid", "7", "--ts", "+5"], "--ts must be"),
    (["--kid", "7", "--ts", "abc"], "--ts must be"),
    (["--kid", "0"], "--kid must be a whole number from 1 to 4294967295"),
    (["--kid", "4294967296"], "--kid must be"),
    (["--kid", "+7"], "--kid must be"),
    (["--kid", "7", "--nonce", "+1+1+1+1+1+1+1+1+1+1+1+1"], "is not hex"),
    (["--kid", "7", "--nonce", "a0a1"], "the nonce must be 12 bytes"),
  ]
  for (extra, message) in sealCases {
    let outcome = thrownMessage {
      _ = try VoipSeal.blob(Options((sealLine + extra)[...], for: .seal))
    }
    try check(
      message.isEmpty ? outcome.isEmpty : outcome.contains(message),
      "seal \(extra) gives \(outcome.debugDescription), not \(message.debugDescription)")
  }

  try check(
    try VoipSeal.expiry(ts: 4_294_967_250_000, rts: 4_294_967_250_000) == UInt32.max,
    "the last expiry that fits in 32 bits is refused")
  let overflowing: [Int64] = [4_294_967_251_000, .max]
  for ts in overflowing {
    try check((try? VoipSeal.expiry(ts: ts, rts: ts)) == nil, "an expiry past 32 bits is accepted")
  }

  try check(try hexBytes("a1B2") == [0xA1, 0xB2], "hex digits are not read")
  let notHex = ["", "a", "+1", "-1", "1 ", " 1", "0x", "1\n", "\u{FF11}\u{FF12}", "gg"]
  for text in notHex {
    try check((try? hexBytes(text)) == nil, "\(text.debugDescription) is accepted as hex")
  }
}

let usage = """
  usage: swift tool/push_test/apns_send.swift <alert|voip|seal|selftest> [options]
    alert  --p8 FILE --key-id ID --token HEX|PUSHKEY [--team-id 5V9UP3J9CK] [--topic im.zuno.chat]
           [--room-id ID] [--event-id ID] [--unread N] [--no-sound] [--production]
    voip   --p8 FILE --key-id ID --token HEX|PUSHKEY [--team-id 5V9UP3J9CK]
           [--topic im.zuno.chat.voip] --key B64 --kid N --room ID --call ID --caller MXID
           [--cname NAME] [--rname NAME] [--kind voice|video|canary] [--nonce HEX]
           [--ts MS] [--rts MS] [--production]
    seal   --key B64 --kid N --room ID --call ID --caller MXID [--cname NAME] [--rname NAME]
           [--kind voice|video|canary] [--nonce HEX] [--ts MS] [--rts MS]
    selftest
  a value that starts with -- goes as --name=value
  """
let arguments = CommandLine.arguments
do {
  guard arguments.count >= 2, let command = Command(rawValue: arguments[1]) else {
    throw ToolError(description: usage)
  }
  let options = try Options(arguments.dropFirst(2), for: command)
  switch command {
  case .alert:
    try await send(.alert, options)
  case .voip:
    try await send(.voip, options)
  case .seal:
    print(Data(try VoipSeal.blob(options)).base64EncodedString())
  case .selftest:
    try selftest()
  }
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
