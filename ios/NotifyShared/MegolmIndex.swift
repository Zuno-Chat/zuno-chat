import Foundation

enum MegolmIndex {
  static func messageIndex(ofCiphertext ciphertext: String) -> UInt32? {
    guard let bytes = decodeBase64(ciphertext), bytes.count > 2, bytes[0] == 0x03,
      bytes[1] == 0x08
    else { return nil }
    var value: UInt64 = 0
    var shift: UInt64 = 0
    var position = 2
    while position < bytes.count, shift <= 28 {
      let byte = bytes[position]
      value |= UInt64(byte & 0x7F) << shift
      if byte & 0x80 == 0 {
        return value <= UInt64(UInt32.max) ? UInt32(value) : nil
      }
      shift += 7
      position += 1
    }
    return nil
  }

  static func decodeBase64(_ text: String) -> [UInt8]? {
    let remainder = text.utf8.count % 4
    guard remainder != 1 else { return nil }
    let padded = remainder == 0 ? text : text + String(repeating: "=", count: 4 - remainder)
    return Data(base64Encoded: padded).map { Array($0) }
  }
}
