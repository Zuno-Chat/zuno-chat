import CryptoKit
import Foundation

enum VoipKind: String, Equatable, Sendable {
  case voice
  case video
}

struct VoipRing: Equatable, Sendable {
  let room: String
  let call: String
  let caller: String
  let cname: String
  let rname: String
  let kind: VoipKind
  let ts: Int64
}

struct VoipBlobHeader: Equatable, Sendable {
  let kid: UInt32
  let expiry: UInt32
}

enum VoipBlobOpen: Equatable, Sendable {
  case opened(VoipBlobHeader, VoipRing)
  case unknownKid(VoipBlobHeader)
  case unknownVersion
  case forged
}

enum VoipBlob {
  static let version: UInt8 = 0x01
  static let headerLength = 9
  static let nonceLength = 12
  static let tagLength = 16
  static let paddedLengths: Set<Int> = [512, 1024]
  private static let label = Data("zuno-voip-v1".utf8)

  static func data(from payload: [AnyHashable: Any]) -> Data? {
    guard let encoded = payload["z"] as? String else { return nil }
    return Data(base64Encoded: encoded)
  }

  static func open(payload: [AnyHashable: Any], key: (UInt32) -> SymmetricKey?) -> VoipBlobOpen {
    guard let blob = data(from: payload) else { return .forged }
    return open(blob, key: key)
  }

  static func header(_ blob: Data) -> VoipBlobHeader? {
    let bytes = [UInt8](blob)
    guard bytes.count >= headerLength, bytes[0] == version else { return nil }
    return VoipBlobHeader(kid: bigEndian(bytes, at: 1), expiry: bigEndian(bytes, at: 5))
  }

  static func open(_ blob: Data, key: (UInt32) -> SymmetricKey?) -> VoipBlobOpen {
    let bytes = [UInt8](blob)
    guard bytes.count >= headerLength else { return .forged }
    guard let header = header(blob) else { return .unknownVersion }
    guard let secret = key(header.kid) else { return .unknownKid(header) }
    guard paddedLengths.contains(bytes.count - headerLength - nonceLength - tagLength) else {
      return .forged
    }
    let plaintext: Data
    do {
      let box = try ChaChaPoly.SealedBox(combined: Data(bytes[headerLength...]))
      plaintext = try ChaChaPoly.open(
        box, using: secret, authenticating: associatedData(Data(bytes[0..<headerLength])))
    } catch {
      CaughtErrors.record("voip blob open", error)
      return .forged
    }
    guard let ring = ring(from: plaintext) else { return .forged }
    return .opened(header, ring)
  }

  private static func ring(from plaintext: Data) -> VoipRing? {
    var trimmed = [UInt8](plaintext)
    while trimmed.last == 0 { trimmed.removeLast() }
    let parsed = CaughtErrors.attempt("voip blob json") {
      try JSONSerialization.jsonObject(with: Data(trimmed))
    }
    guard
      let object = parsed as? [String: Any],
      let room = object["room"] as? String, !room.isEmpty,
      let call = object["call"] as? String, !call.isEmpty,
      let caller = object["caller"] as? String, !caller.isEmpty,
      let kindName = object["kind"] as? String, let kind = VoipKind(rawValue: kindName),
      let ts = (object["ts"] as? NSNumber)?.int64Value
    else { return nil }
    return VoipRing(
      room: room, call: call, caller: caller, cname: object["cname"] as? String ?? "",
      rname: object["rname"] as? String ?? "", kind: kind, ts: ts)
  }

  private static func associatedData(_ header: Data) -> Data {
    var data = label
    data.append(header)
    return data
  }

  private static func bigEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }
}
