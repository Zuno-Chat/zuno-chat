import Foundation

enum MegolmDecryptOutcome: Equatable, Sendable {
  case plaintext(String)
  case failed
  case unavailable
  case rejected
}

protocol MegolmDecrypting: Sendable {
  func decrypt(pickle: String, userId: String, ciphertext: String) -> MegolmDecryptOutcome
}

enum MegolmPickleKey {
  static func forUser(_ userId: String) -> [UInt8] {
    var key = [UInt8](repeating: 0, count: 32)
    for (offset, unit) in userId.utf16.prefix(32).enumerated() {
      key[offset] = UInt8(truncatingIfNeeded: unit)
    }
    return key
  }
}

final class VodozemacMegolm: MegolmDecrypting, @unchecked Sendable {
  typealias DecryptFunction =
    @convention(c) (
      UnsafePointer<CChar>?, UnsafePointer<UInt8>?, UnsafePointer<CChar>?
    ) -> ZunoMegolmResult
  typealias FreeFunction = @convention(c) (ZunoMegolmResult) -> Void

  static let defaultPath = "@rpath/flutter_vodozemac.framework/flutter_vodozemac"
  static let maxCiphertextBytes = 64 * 1024
  static let maxPickleBytes = 16 * 1024
  static let shared = VodozemacMegolm()

  private let decryptFunction: DecryptFunction?
  private let freeFunction: FreeFunction?

  init(path: String = VodozemacMegolm.defaultPath) {
    guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
      let decrypt = dlsym(handle, "ios_decrypt_event"),
      let free = dlsym(handle, "ios_free_result")
    else {
      decryptFunction = nil
      freeFunction = nil
      return
    }
    decryptFunction = unsafeBitCast(decrypt, to: DecryptFunction.self)
    freeFunction = unsafeBitCast(free, to: FreeFunction.self)
  }

  var isAvailable: Bool { decryptFunction != nil && freeFunction != nil }

  func decrypt(pickle: String, userId: String, ciphertext: String) -> MegolmDecryptOutcome {
    guard let decryptFunction, let freeFunction else { return .unavailable }
    guard Self.acceptable(pickle, limit: Self.maxPickleBytes),
      Self.acceptable(ciphertext, limit: Self.maxCiphertextBytes)
    else { return .rejected }
    let key = MegolmPickleKey.forUser(userId)
    let result = pickle.withCString { picklePointer in
      key.withUnsafeBufferPointer { keyPointer in
        ciphertext.withCString { ciphertextPointer in
          decryptFunction(picklePointer, keyPointer.baseAddress, ciphertextPointer)
        }
      }
    }
    defer { freeFunction(result) }
    guard let plaintext = result.plaintext else { return .failed }
    return .plaintext(String(cString: plaintext))
  }

  static func acceptable(_ text: String, limit: Int) -> Bool {
    let bytes = text.utf8
    return !bytes.isEmpty && bytes.count <= limit && !bytes.contains(0)
  }
}
