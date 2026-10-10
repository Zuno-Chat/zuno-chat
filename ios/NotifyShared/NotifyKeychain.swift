import CryptoKit
import Foundation
import Security

enum KeychainRead: Equatable, Sendable {
  case found(Data)
  case missing
  case locked
  case failed(OSStatus)
}

protocol KeychainBackend: Sendable {
  func read(service: String, account: String, accessGroup: String?) -> KeychainRead
  func write(_ data: Data, service: String, account: String, accessGroup: String?) -> OSStatus
  func delete(service: String, accessGroup: String?) -> OSStatus
}

struct SystemKeychain: KeychainBackend {
  static func isLocked(_ status: OSStatus) -> Bool {
    status == errSecInteractionNotAllowed || status == errSecNotAvailable
  }

  func read(service: String, account: String, accessGroup: String?) -> KeychainRead {
    var query = Self.query(service: service, account: account, accessGroup: accessGroup)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return .failed(status) }
      return .found(data)
    case errSecItemNotFound:
      return .missing
    case errSecInteractionNotAllowed:
      return .locked
    default:
      Self.checked(status, "keychain read \(service)")
      return .failed(status)
    }
  }

  func write(_ data: Data, service: String, account: String, accessGroup: String?) -> OSStatus {
    let query = Self.query(service: service, account: account, accessGroup: accessGroup)
    let update = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    guard update == errSecItemNotFound else {
      return Self.checked(update, "keychain update \(service)")
    }
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return Self.checked(SecItemAdd(item as CFDictionary, nil), "keychain add \(service)")
  }

  func delete(service: String, accessGroup: String?) -> OSStatus {
    let query = Self.query(service: service, account: nil, accessGroup: accessGroup)
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecItemNotFound
      ? status : Self.checked(status, "keychain delete \(service)")
  }

  @discardableResult
  static func checked(_ status: OSStatus, _ label: String) -> OSStatus {
    if status != errSecSuccess, !isLocked(status) {
      CaughtErrors.record(label, NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
    }
    return status
  }

  private static func query(service: String, account: String?, accessGroup: String?)
    -> [String: Any]
  {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    if let account { query[kSecAttrAccount as String] = account }
    if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
    return query
  }
}

struct NotifySecrets: Codable, Equatable, Sendable {
  var rmKey: Data
  var installKey: Data
  var credential: String?
  var credentialExpiresTs: Int64?

  private enum CodingKeys: String, CodingKey {
    case rmKey = "rm_key"
    case installKey = "install_key"
    case credential
    case credentialExpiresTs = "credential_expires_ts"
  }

  static func generate() -> NotifySecrets {
    NotifySecrets(rmKey: randomKey(), installKey: randomKey())
  }

  var readModelKey: SymmetricKey { SymmetricKey(data: rmKey) }
  var tokenKey: SymmetricKey { SymmetricKey(data: installKey) }

  private static func randomKey() -> Data {
    SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
  }
}

enum NotifySecretsRead: Equatable, Sendable {
  case ready(NotifySecrets)
  case created(NotifySecrets)
  case locked
  case unavailable
}

struct NotifyKeychain: Sendable {
  static let service = "im.zuno.chat.notify"
  static let account = "notify"

  let accessGroup: String?
  let backend: any KeychainBackend

  init(accessGroup: String?, backend: any KeychainBackend = SystemKeychain()) {
    self.accessGroup = accessGroup
    self.backend = backend
  }

  func load(createIfMissing: Bool) -> NotifySecretsRead {
    switch backend.read(service: Self.service, account: Self.account, accessGroup: accessGroup) {
    case .found(let data):
      let secrets = CaughtErrors.attempt("notify keychain decode") {
        try JSONDecoder().decode(NotifySecrets.self, from: data)
      }
      if let secrets, secrets.rmKey.count == 32, secrets.installKey.count == 32 {
        return .ready(secrets)
      }
      return createIfMissing ? create() : .unavailable
    case .missing:
      return createIfMissing ? create() : .unavailable
    case .locked:
      return .locked
    case .failed:
      return .unavailable
    }
  }

  @discardableResult
  func save(_ secrets: NotifySecrets) -> Bool {
    let data = CaughtErrors.attempt("notify keychain encode") { try JSONEncoder().encode(secrets) }
    guard let data else { return false }
    return backend.write(
      data, service: Self.service, account: Self.account, accessGroup: accessGroup)
      == errSecSuccess
  }

  func delete() {
    _ = backend.delete(service: Self.service, accessGroup: accessGroup)
  }

  private func create() -> NotifySecretsRead {
    let secrets = NotifySecrets.generate()
    return save(secrets) ? .created(secrets) : .unavailable
  }
}
