import CryptoKit
import Foundation
import Security

@testable import Runner

final class MemoryKeychain: KeychainBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String: Data] = [:]
  private var lockedNow = false

  var locked: Bool {
    get { guarded { lockedNow } }
    set { guarded { lockedNow = newValue } }
  }

  func stored(service: String, account: String) -> Data? {
    guarded { items["\(service)|\(account)"] }
  }

  func store(_ data: Data, service: String, account: String) {
    guarded { items["\(service)|\(account)"] = data }
  }

  func read(service: String, account: String, accessGroup: String?) -> KeychainRead {
    guarded {
      if lockedNow { return .locked }
      return items["\(service)|\(account)"].map(KeychainRead.found) ?? .missing
    }
  }

  func write(_ data: Data, service: String, account: String, accessGroup: String?) -> OSStatus {
    guarded {
      if lockedNow { return errSecInteractionNotAllowed }
      items["\(service)|\(account)"] = data
      return errSecSuccess
    }
  }

  func delete(service: String, accessGroup: String?) -> OSStatus {
    guarded {
      items = items.filter { !$0.key.hasPrefix("\(service)|") }
      return errSecSuccess
    }
  }

  private func guarded<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

func makeTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "notify-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

enum VoipBlobFixture {
  static let key = SymmetricKey(data: Data(0x00...0x1f))
  static let kid: UInt32 = 16_909_060
  static let expiry: UInt32 = 1_790_000_045
  static let nonce = try! ChaChaPoly.Nonce(data: Data(0xa0...0xab))
  static let json =
    #"{"room":"!abc:zuno.im","call":"c1","caller":"@alice:zuno.im","cname":"Alice","rname":"","kind":"video","ts":1790000000000,"rts":1789999999000}"#
  static let digest = "aaf898f4941c4ff73dd0b30839264042535a098823be3a5ed024339fc58b6a80"

  static func seal(
    _ json: String = json, kid: UInt32 = kid, expiry: UInt32 = expiry,
    key: SymmetricKey = key, nonce: ChaChaPoly.Nonce = nonce, version: UInt8 = 0x01,
    padTo length: Int? = nil
  ) -> Data {
    var header = Data([version])
    header.append(contentsOf: withUnsafeBytes(of: kid.bigEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: expiry.bigEndian) { Array($0) })
    var padded = Data(json.utf8)
    let target = length ?? (padded.count > 512 ? 1024 : 512)
    padded.append(Data(repeating: 0, count: max(0, target - padded.count)))
    var aad = Data("zuno-voip-v1".utf8)
    aad.append(header)
    let box = try! ChaChaPoly.seal(padded, using: key, nonce: nonce, authenticating: aad)
    var blob = header
    blob.append(box.combined)
    return blob
  }

  static func hex(_ data: some Sequence<UInt8>) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}
