import XCTest

@testable import Runner

final class NseModelsTests: XCTestCase {
  private func data(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
  }

  func testMetaReadsThePhaseThreeFields() throws {
    let meta = try XCTUnwrap(
      NseMeta.decode(
        data([
          "v": 1, "user": "@mwong:zuno.im", "device": "D", "ringtone": false,
          "heartbeat_ms": 1_790_000_000_000, "base_url": "https://zuno.im", "level": "name",
          "notify": "mentions", "tone": false, "unread": ["t1", "t2"],
          "mention": [
            "mxid": "@mwong:zuno.im", "display_name": "Mia",
            "keywords": [["pattern": "zuno", "highlight": true]],
            "rules": [".m.rule.roomnotif": false],
          ],
        ])))

    XCTAssertEqual(meta.user, "@mwong:zuno.im")
    XCTAssertEqual(meta.baseUrl, "https://zuno.im")
    XCTAssertEqual(meta.level, .name)
    XCTAssertTrue(meta.mentionsOnly)
    XCTAssertFalse(meta.tone)
    XCTAssertFalse(meta.ringtone)
    XCTAssertEqual(meta.unread, ["t1", "t2"])
    XCTAssertEqual(meta.heartbeatMs, 1_790_000_000_000)
    XCTAssertEqual(meta.mention?.keywords, [.init(pattern: "zuno", highlight: true)])
    XCTAssertEqual(meta.mention?.rules, [".m.rule.roomnotif": false])
  }

  func testMetaWithOnlyTheBaseUrlDefaultsToFullContentEveryMessageAndBothTones() throws {
    let meta = try XCTUnwrap(
      NseMeta.decode(data(["v": 1, "user": "@mwong:zuno.im", "base_url": "https://zuno.im"])))

    XCTAssertEqual(meta.level, .full)
    XCTAssertFalse(meta.mentionsOnly)
    XCTAssertTrue(meta.tone)
    XCTAssertTrue(meta.ringtone)
    XCTAssertNil(meta.unread)
    XCTAssertNil(meta.mention)
  }

  func testAPresentLevelThatIsNotAKnownStringReadsAsNothingWhileAnAbsentOneReadsAsFull() throws {
    for level: Any in ["later", 7, NSNull()] {
      let meta = try XCTUnwrap(
        NseMeta.decode(
          data(["v": 1, "user": "@mwong:zuno.im", "base_url": "https://zuno.im", "level": level])))

      XCTAssertEqual(meta.level, PreviewLevel.none, "\(level)")
    }
    let absent = try XCTUnwrap(
      NseMeta.decode(data(["v": 1, "user": "@mwong:zuno.im", "base_url": "https://zuno.im"])))

    XCTAssertEqual(absent.level, PreviewLevel.full)
  }

  func testAPhaseTwoMetaLeavesTheExtensionOff() {
    XCTAssertNil(
      NseMeta.decode(
        data([
          "v": 1, "user": "@mwong:zuno.im", "device": "D", "ringtone": true,
          "voip_current": true, "heartbeat_ms": 1,
        ])))
    XCTAssertNil(
      NseMeta.decode(data(["v": 1, "user": "@mwong:zuno.im", "base_url": ""])))
  }

  func testMetaOfAnotherVersionOrWithoutAUserIsUnreadable() {
    XCTAssertNil(NseMeta.decode(data(["v": 2, "user": "@mwong:zuno.im", "base_url": "https://x"])))
    XCTAssertNil(NseMeta.decode(data(["v": 1, "base_url": "https://x"])))
    XCTAssertNil(NseMeta.decode(Data("not json".utf8)))
  }

  func testARoomFileKeepsItsSessionsAndNotifiers() throws {
    let room = try XCTUnwrap(
      NseRoomFile.decode(
        data([
          "v": 1, "room": "!abc:zuno.im", "title": "Design team", "dm": false, "partner": "",
          "sessions": [
            [
              "session_id": "s1", "sender": "@alice:zuno.im", "sender_key": "k1",
              "first_index": 4, "pickle": "p1",
            ]
          ],
          "notifiers": ["@admin:zuno.im"],
        ])))

    XCTAssertEqual(room.title, "Design team")
    XCTAssertEqual(
      room.session("s1"),
      NseSession(
        sessionId: "s1", sender: "@alice:zuno.im", senderKey: "k1", firstIndex: 4, pickle: "p1"))
    XCTAssertNil(room.session("s2"))
    XCTAssertEqual(room.notifiers, ["@admin:zuno.im"])
  }

  func testARoomFileSkipsSessionsMissingAPickleOrIndex() throws {
    let room = try XCTUnwrap(
      NseRoomFile.decode(
        data([
          "v": 1, "room": "!abc:zuno.im",
          "sessions": [
            ["session_id": "s1", "first_index": 0], ["session_id": "s2", "pickle": "p"],
          ],
        ])))

    XCTAssertTrue(room.sessions.isEmpty)
    XCTAssertFalse(room.dm)
  }

  func testAPushReadsSygnalIdsAndSpotsTheTestPrefix() {
    let push = NsePush(
      id: "p", userInfo: ["room_id": "!r:x", "event_id": "$zuno_test_3", "unread_count": 2],
      receivedMs: 9)

    XCTAssertEqual(push.roomId, "!r:x")
    XCTAssertTrue(push.isTest)
    XCTAssertFalse(NsePush(id: "p", userInfo: ["event_id": "$e"], receivedMs: 9).isTest)
    XCTAssertFalse(NsePush(id: "p", userInfo: [:], receivedMs: 9).isTest)
  }

  func testJsonKeepsBooleansApartFromNumbers() throws {
    let json = try XCTUnwrap(NseJson.parse(Data(#"{"a":true,"b":1,"c":1.5}"#.utf8)))

    XCTAssertEqual(json["a"], .bool(true))
    XCTAssertEqual(json["b"]?.int64, 1)
    XCTAssertNil(json["c"]?.int64)
    XCTAssertNil(json["a"]?.int64)
  }
}
