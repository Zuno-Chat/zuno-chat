import Foundation
import Security

enum FirstUnlockProbe {
  static let service = "im.zuno.chat.unlock-probe"
  static let account = "probe"

  static func passed() -> Bool {
    let status = read()
    guard status == errSecItemNotFound else {
      return passed(status: SystemKeychain.checked(status, "first unlock probe read"))
    }
    return passed(status: SystemKeychain.checked(create(), "first unlock probe create"))
  }

  static func passed(status: OSStatus) -> Bool {
    !SystemKeychain.isLocked(status)
  }

  private static var base: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func read() -> OSStatus {
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &result)
  }

  private static func create() -> OSStatus {
    var item = base
    item[kSecValueData as String] = Data([1])
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    return status == errSecDuplicateItem ? errSecSuccess : status
  }
}
