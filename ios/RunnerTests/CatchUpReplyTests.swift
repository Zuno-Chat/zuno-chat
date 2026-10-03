import XCTest

@testable import Runner

final class CatchUpReplyTests: XCTestCase {
  private func item(
    room: String = "!r:hs", event: String = "$e1", ts: Any = 1_790_000_000_000,
    eventRoom: Any? = nil, eventId: Any? = nil
  ) -> [String: Any] {
    var inner: [String: Any] = [
      "type": "m.room.encrypted", "origin_server_ts": ts, "content": [String: Any](),
    ]
    if let eventRoom { inner["room_id"] = eventRoom }
    if let eventId { inner["event_id"] = eventId }
    return [
      "room_id": room, "event_id": event, "event": inner, "sender_name": "Alice",
      "room_name": "Design team", "is_dm": false, "highlight": true, "sound": true,
    ]
  }

  func testAMissedEventKeepsItsRoomEventTimeNamesAndFlags() throws {
    let reply = CatchUpReply.parse([
      "status": "ok", "missed": [item(eventRoom: "!r:hs", eventId: "$e1")],
    ])
    let missed = try XCTUnwrap(reply.missed.first)
    XCTAssertEqual(missed.roomId, "!r:hs")
    XCTAssertEqual(missed.eventId, "$e1")
    XCTAssertEqual(missed.originServerTs, 1_790_000_000_000)
    XCTAssertEqual(missed.seconds, 1_790_000_000)
    XCTAssertEqual(missed.senderName, "Alice")
    XCTAssertEqual(missed.roomName, "Design team")
    XCTAssertFalse(missed.isDm)
    XCTAssertTrue(missed.highlight)
    XCTAssertTrue(missed.sound)
    XCTAssertEqual(missed.item["event_id"] as? String, "$e1")
  }

  func testReadRoomsCarryTheirReceiptTimes() {
    let reply = CatchUpReply.parse([
      "read_rooms": [
        ["room_id": "!a:hs", "receipt_ts": 1_790_000_000_500],
        ["room_id": "!b:hs", "receipt_ts": 1_790_000_001_000],
      ]
    ])
    XCTAssertEqual(
      reply.readRooms,
      [
        ReadRoom(roomId: "!a:hs", receiptTs: 1_790_000_000_500),
        ReadRoom(roomId: "!b:hs", receiptTs: 1_790_000_001_000),
      ])
  }

  func testAReadRoomWithoutAKnownReceiptIsLeftOut() {
    let reply = CatchUpReply.parse([
      "read_rooms": [
        ["room_id": "!a:hs", "receipt_ts": 0],
        ["room_id": "!b:hs", "receipt_ts": 1_790_000_000_000],
      ]
    ])
    XCTAssertEqual(reply.readRooms, [ReadRoom(roomId: "!b:hs", receiptTs: 1_790_000_000_000)])
  }

  func testAReplyWithoutExtrasHasNothingToCatchUp() {
    let reply = CatchUpReply.parse(["status": "gone", "server_ts": 1])
    XCTAssertTrue(reply.missed.isEmpty)
    XCTAssertTrue(reply.readRooms.isEmpty)
  }

  func testExtrasOfTheWrongShapeAreIgnored() {
    let bodies: [[String: Any]] = [
      ["missed": "x", "read_rooms": 7],
      ["missed": ["a": 1], "read_rooms": NSNull()],
      ["missed": [1, "two", NSNull()], "read_rooms": [[1]]],
    ]
    for body in bodies {
      let reply = CatchUpReply.parse(body)
      XCTAssertTrue(reply.missed.isEmpty)
      XCTAssertTrue(reply.readRooms.isEmpty)
    }
  }

  func testOnlyTheBrokenItemIsDropped() {
    let broken: [[String: Any]] = [
      item(room: "r:hs"), item(event: "e1"), item(ts: 0), item(ts: -5),
      item(ts: "1790000000000"), item(eventRoom: "!other:hs"), item(eventId: "$other"),
      ["room_id": "!r:hs", "event_id": "$e9"],
    ]
    let reply = CatchUpReply.parse(["missed": broken + [item(event: "$good")]])
    XCTAssertEqual(reply.missed.map(\.eventId), ["$good"])
  }

  func testAtMostTwentyMissedAndFiftyReadRoomsAreRead() {
    let missed = (0..<5000).map { item(event: "$e\($0)") }
    let reads: [[String: Any]] = (0..<5000).map {
      ["room_id": "!r\($0):hs", "receipt_ts": 1_790_000_000_000]
    }
    let reply = CatchUpReply.parse(["missed": missed, "read_rooms": reads])
    XCTAssertEqual(reply.missed.map(\.eventId), (0..<20).map { "$e\($0)" })
    XCTAssertEqual(reply.readRooms.count, 50)
  }

  func testValuesDecodedFromJsonAreRead() throws {
    let json = #"""
      {"status":"read","receipt_ts":1,
       "missed":[{"room_id":"!r:hs","event_id":"$e","is_dm":true,"highlight":false,"sound":true,
                  "event":{"event_id":"$e","room_id":"!r:hs","origin_server_ts":1790000000999,"content":{}}}],
       "read_rooms":[{"room_id":"!r:hs","receipt_ts":1790000000000}]}
      """#
    let body = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let reply = CatchUpReply.parse(body)
    XCTAssertEqual(reply.missed.first?.originServerTs, 1_790_000_000_999)
    XCTAssertEqual(reply.missed.first?.isDm, true)
    XCTAssertEqual(reply.readRooms.first?.receiptTs, 1_790_000_000_000)
  }
}
