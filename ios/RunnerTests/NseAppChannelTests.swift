import XCTest

@testable import Runner

final class NseAppChannelTests: XCTestCase {
  private let claims: [Any] = [
    ["kind": "event", "id": "$a"], ["kind": "invite", "id": "!r"], ["kind": "room", "id": "!x"],
    ["kind": "event"], ["kind": "event", "id": ""], "$b",
  ]

  private func store(_ files: NseFakeFiles) -> NseAppStore {
    NseAppStore(state: NseStateStore(files: files), hashing: NseFakeHashing())
  }

  func testTheAppMethodsReadTheirArguments() throws {
    guard
      case .writeShown(let written) = try XCTUnwrap(
        NseAppRequest(method: "writeShown", arguments: ["claims": claims]))
    else { return XCTFail("not writeShown") }
    XCTAssertEqual(written, [.event("$a"), .invite("!r")])

    guard
      case .shownByExtension(let asked) = try XCTUnwrap(
        NseAppRequest(method: "shownByExtension", arguments: ["claims": claims]))
    else { return XCTFail("not shownByExtension") }
    XCTAssertEqual(asked, [.event("$a"), .invite("!r"), nil, nil, nil, nil])

    guard
      case .setCredential(let credential, let expires) = try XCTUnwrap(
        NseAppRequest(
          method: "setCredential",
          arguments: ["credential": "c", "expires_ts": NSNumber(value: 1_792_592_000_000)]))
    else { return XCTFail("not setCredential") }
    XCTAssertEqual(credential, "c")
    XCTAssertEqual(expires, 1_792_592_000_000)

    guard
      case .syncBadge(let unread) = try XCTUnwrap(
        NseAppRequest(method: "syncBadge", arguments: ["unread": ["t1"]]))
    else { return XCTFail("not syncBadge") }
    XCTAssertEqual(unread, ["t1"])
  }

  func testAClaimIsTheEventOrTheInvitedRoom() {
    XCTAssertEqual(NseClaim.event("$a").key, "$a")
    XCTAssertEqual(NseClaim.invite("!r").key, "invite:!r")
    XCTAssertEqual(NseClaim(["kind": "invite", "id": "!r"]), .invite("!r"))
    XCTAssertNil(NseClaim(["kind": "invite", "id": 7]))
    XCTAssertNil(NseClaim(nil))
  }

  func testOnlyTheShownByExtensionAskJumpsTheQueue() {
    XCTAssertEqual(NseAppRequest.shownByExtension([]).priority, .userInitiated)
    for request in [
      NseAppRequest.writeShown([]), .takeMarks, .readOutcomes, .setCredential(nil, nil),
      .syncBadge([]),
    ] {
      XCTAssertEqual(request.priority, .utility)
    }
  }

  func testTheAppRecordsTheClaimsItShowedHashed() {
    let files = NseFakeFiles()

    store(files).writeShown([.event("$a"), .invite("!r")])

    XCTAssertEqual(SeenSets.tokens(files.read(NotifyFile.shownApp)), ["e$a", "einvite:!r"])
    XCTAssertNil(files.read(NotifyFile.shownNse))
  }

  func testEachAnswerSitsAtItsClaimsPlace() {
    let files = NseFakeFiles()
    files.put(NotifyFile.shownNse, ["v": 1, "e": ["e$nse", "einvite:!r"]])
    files.put(NotifyFile.shownApp, ["v": 1, "e": ["e$app"]])
    let store = store(files)

    XCTAssertEqual(
      store.shownByExtension([
        .event("$app"), .invite("!r"), .event("$other"), .event("$nse"), .invite("$nse"),
      ]),
      [false, true, false, true, false])
    XCTAssertEqual(
      NseAppRequest.answers([.event("$nse"), nil, .invite("!r"), nil], from: store),
      [true, false, true, false])
    XCTAssertEqual(NseAppRequest.answers([.event("$nse"), nil], from: nil), [false, false])
  }

  func testAHiddenAlertRecordsEveryClaimItCarriesAndOneWithoutClaimsNothing() {
    let files = NseFakeFiles()
    let store = store(files)

    XCTAssertTrue(store.recordHidden(NseTestData.delivered("msg", e: "e$m")))
    XCTAssertTrue(
      store.recordHidden(
        NseTestData.delivered("inv", e: "e$member", c: "einvite:!r", k: "inv")))
    XCTAssertFalse(store.recordHidden(NseTestData.delivered("sys", e: nil, k: "sys")))

    XCTAssertEqual(
      SeenSets.tokens(files.read(NotifyFile.hiddenApp)), ["e$m", "e$member", "einvite:!r"])
    XCTAssertEqual(files.writes(NotifyFile.hiddenApp), 2)
  }

  func testAnInvitationHiddenInFrontIsNoLongerTheExtensionsWhileAMessageStaysIt() {
    let files = NseFakeFiles()
    files.put(NotifyFile.shownNse, ["v": 1, "e": ["e$member", "einvite:!r", "e$message"]])
    let store = store(files)

    _ = store.recordHidden(
      NseTestData.delivered("inv", t: "t!r", e: "e$member", c: "einvite:!r", k: "inv"))

    XCTAssertEqual(
      store.shownByExtension([.invite("!r"), .event("$member"), .event("$message")]),
      [false, false, true])
    XCTAssertEqual(
      SeenSets.tokens(files.read(NotifyFile.shownNse)), ["e$member", "einvite:!r", "e$message"])
  }

  func testClearingTheCredentialAndBareMethodsNeedNoArguments() throws {
    guard
      case .setCredential(let credential, let expires) = try XCTUnwrap(
        NseAppRequest(method: "setCredential", arguments: ["credential": NSNull()]))
    else { return XCTFail("not setCredential") }
    XCTAssertNil(credential)
    XCTAssertNil(expires)
    XCTAssertNotNil(NseAppRequest(method: "takeMarks", arguments: nil))
    XCTAssertNotNil(NseAppRequest(method: "readOutcomes", arguments: nil))
    guard
      case .shownByExtension(let asked) = try XCTUnwrap(
        NseAppRequest(method: "shownByExtension", arguments: nil))
    else { return XCTFail("not shownByExtension") }
    XCTAssertEqual(asked, [])
  }

  func testPhaseTwoAndUnknownMethodsAreLeftToTheirOwner() {
    for method in ["threadKey", "writeMeta", "writeRoom", "deleteRoom", "wipe", "removeDelivered"] {
      XCTAssertNil(NseAppRequest(method: method, arguments: [:]), method)
    }
  }
}
