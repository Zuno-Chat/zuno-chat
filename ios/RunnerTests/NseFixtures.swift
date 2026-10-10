import Foundation
import XCTest

@testable import Runner

enum NseFixtures {
  static func json(_ name: String) throws -> NseJson {
    let data = try Data(contentsOf: ContractFixture.directory.appendingPathComponent(name))
    return try XCTUnwrap(NseJson.parse(data))
  }

  static func cases(_ name: String) throws -> [NseJson] {
    try XCTUnwrap(json(name)["cases"]?.array)
  }

  static func data(_ value: NseJson) -> Data {
    (try? JSONSerialization.data(withJSONObject: any(value), options: [.sortedKeys])) ?? Data()
  }

  static func dispatchEvent(_ vector: NseJson, now: Int64) throws -> NseEvent {
    let raw = try XCTUnwrap(vector["event"])
    let sender = try XCTUnwrap(vector["sender"]?.string)
    var inviteState: [NseJson] = []
    if let name = vector["room"]?["name"]?.string {
      inviteState.append(
        .object(["type": .string("m.room.name"), "content": .object(["name": .string(name)])]))
    }
    if let senderName = vector["sender_name"]?.string {
      inviteState.append(
        .object([
          "type": .string("m.room.member"), "state_key": .string(sender),
          "content": .object(["displayname": .string(senderName)]),
        ]))
    }
    return NseEvent(
      eventId: "$vector", roomId: "!abc:zuno.im", type: try XCTUnwrap(raw["type"]?.string),
      sender: sender, originServerTs: now - (vector["age_ms"]?.int64 ?? 0),
      stateKey: raw["state_key"]?.string, redacted: raw["redacted"]?.bool ?? false,
      content: raw["content"] ?? .object([:]), inviteRoomState: inviteState)
  }

  static func any(_ value: NseJson) -> Any {
    switch value {
    case .string(let text): return text
    case .number(let number): return number.rounded() == number ? Int64(number) as Any : number
    case .bool(let flag): return flag
    case .null: return NSNull()
    case .array(let items): return items.map(any)
    case .object(let fields): return fields.mapValues(any)
    }
  }
}
