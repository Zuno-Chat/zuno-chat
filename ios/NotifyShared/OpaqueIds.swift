import CryptoKit
import Foundation

enum OpaqueIds {
  static let length = 32

  static func roomToken(_ roomId: String, installKey: SymmetricKey) -> String {
    token(roomId, installKey: installKey)
  }

  static func eventToken(_ eventId: String, installKey: SymmetricKey) -> String {
    token(eventId, installKey: installKey)
  }

  static func ringToken(_ callUUID: UUID, installKey: SymmetricKey) -> String {
    token(callUUID.uuidString, installKey: installKey)
  }

  private static func token(_ value: String, installKey: SymmetricKey) -> String {
    let code = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: installKey)
    return String(code.map { String(format: "%02x", $0) }.joined().prefix(length))
  }
}
