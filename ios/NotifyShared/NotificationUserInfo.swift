import Foundation

enum NotificationUserInfo {
  static func text(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return string
  }

  static func seconds(_ value: Any?) -> Int? {
    if let text = value as? String { return Int(text) }
    return (value as? NSNumber)?.intValue
  }

  static func messagePayload(in userInfo: [AnyHashable: Any]) -> [String: Any]? {
    guard let json = userInfo["payload"] as? String,
      let decoded = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
      decoded["type"] as? String == "message"
    else { return nil }
    return decoded
  }
}
