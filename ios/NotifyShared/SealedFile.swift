import CryptoKit
import Foundation

enum SealedFileError: Error, Equatable {
  case truncated
  case unknownVersion
  case unauthentic
}

enum SealedFile {
  static let version: UInt8 = 0x01
  private static let overhead = 1 + 12 + 16

  static func seal(
    _ plaintext: Data, name: String, key: SymmetricKey,
    nonce: ChaChaPoly.Nonce = ChaChaPoly.Nonce()
  ) throws -> Data {
    let box = try ChaChaPoly.seal(
      plaintext, using: key, nonce: nonce, authenticating: associatedData(name))
    var sealed = Data([version])
    sealed.append(box.combined)
    return sealed
  }

  static func open(_ sealed: Data, name: String, key: SymmetricKey) throws -> Data {
    guard sealed.count >= overhead else { throw SealedFileError.truncated }
    guard sealed.first == version else { throw SealedFileError.unknownVersion }
    do {
      let box = try ChaChaPoly.SealedBox(combined: sealed.dropFirst())
      return try ChaChaPoly.open(box, using: key, authenticating: associatedData(name))
    } catch {
      throw SealedFileError.unauthentic
    }
  }

  private static func associatedData(_ name: String) -> Data {
    var data = Data(name.utf8)
    data.append(version)
    return data
  }
}
