import CryptoKit
import Foundation

enum CallIdentity {
  private static let namespace = UUID(uuidString: "5C2B7E0A-3D4F-4B8E-9A61-2F7C8D0E1B34")!

  static func uuid(roomId: String, callId: String) -> UUID {
    var name = withUnsafeBytes(of: namespace.uuid) { Array($0) }
    name.append(contentsOf: key(roomId: roomId, callId: callId).utf8)
    var hash = Array(Insecure.SHA1.hash(data: name).prefix(16))
    hash[6] = (hash[6] & 0x0F) | 0x50
    hash[8] = (hash[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
        hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
      ))
  }

  static func key(roomId: String, callId: String) -> String {
    "\(roomId)\n\(callId)"
  }
}
