import CryptoKit
import Foundation
import Security

struct VoipKeys: Codable, Equatable, Sendable {
  var kid: UInt32
  var key: Data
  var prevKid: UInt32?
  var prevKey: Data?
  var prevUntilMs: Int64?

  private enum CodingKeys: String, CodingKey {
    case kid
    case key
    case prevKid = "prev_kid"
    case prevKey = "prev_key"
    case prevUntilMs = "prev_until_ms"
  }

  func key(for kid: UInt32, nowMs: Int64) -> SymmetricKey? {
    if kid == self.kid { return SymmetricKey(data: key) }
    guard kid == prevKid, let prevKey, (prevUntilMs ?? .max) > nowMs else { return nil }
    return SymmetricKey(data: prevKey)
  }
}

enum VoipKeysRead: Equatable, Sendable {
  case ready(VoipKeys)
  case missing
  case locked
  case unavailable
}

struct VoipKeyStore: Sendable {
  static let service = "im.zuno.chat.voip"
  static let account = "voip"
  static let previousKeyGrace: Int64 = 24 * 60 * 60 * 1000

  let backend: any KeychainBackend
  let newKid: @Sendable () -> UInt32

  init(
    backend: any KeychainBackend = SystemKeychain(),
    newKid: @escaping @Sendable () -> UInt32 = { UInt32.random(in: 1...UInt32.max) }
  ) {
    self.backend = backend
    self.newKid = newKid
  }

  func load() -> VoipKeysRead {
    switch backend.read(service: Self.service, account: Self.account, accessGroup: nil) {
    case .found(let data):
      guard let keys = try? JSONDecoder().decode(VoipKeys.self, from: data), keys.key.count == 32
      else { return .missing }
      return .ready(keys)
    case .missing:
      return .missing
    case .locked:
      return .locked
    case .failed:
      return .unavailable
    }
  }

  func current() -> VoipKeysRead {
    switch load() {
    case .missing:
      let keys = VoipKeys(kid: freshKid(avoiding: []), key: Self.randomKey())
      return save(keys) ? .ready(keys) : .unavailable
    case let other:
      return other
    }
  }

  func rotate() -> VoipKeys? {
    guard case .ready(let old) = current() else { return nil }
    let keys = VoipKeys(
      kid: freshKid(avoiding: [old.kid]), key: Self.randomKey(), prevKid: old.kid,
      prevKey: old.key, prevUntilMs: nil)
    return save(keys) ? keys : nil
  }

  func acknowledge(kid: UInt32, nowMs: Int64) -> VoipKeys? {
    guard case .ready(var keys) = load(), keys.kid == kid else { return nil }
    if keys.prevKid != nil, keys.prevUntilMs == nil {
      keys.prevUntilMs = nowMs + Self.previousKeyGrace
      guard save(keys) else { return nil }
    }
    return keys
  }

  func delete() {
    _ = backend.delete(service: Self.service, accessGroup: nil)
  }

  private func save(_ keys: VoipKeys) -> Bool {
    guard let data = try? JSONEncoder().encode(keys) else { return false }
    return backend.write(data, service: Self.service, account: Self.account, accessGroup: nil)
      == errSecSuccess
  }

  private func freshKid(avoiding used: Set<UInt32>) -> UInt32 {
    var kid = newKid()
    while kid == 0 || used.contains(kid) {
      kid = newKid()
    }
    return kid
  }

  private static func randomKey() -> Data {
    SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
  }
}
