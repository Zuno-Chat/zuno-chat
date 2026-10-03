@preconcurrency import CallKit
import Foundation

@testable import Runner

@MainActor
final class FakeCallProvider: CallProviding {
  struct Report {
    let uuid: UUID
    let name: String?
    let handle: String?
    let video: Bool
  }

  var reports: [Report] = []
  var updates: [Report] = []
  var ended: [(UUID, CXCallEndedReason)] = []
  var configurations = 0
  private var completions: [@MainActor @Sendable ((any Error)?) -> Void] = []

  func setConfiguration(_ configuration: CXProviderConfiguration) {
    configurations += 1
  }

  func reportNewIncomingCall(
    _ uuid: UUID, update: CXCallUpdate,
    completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
  ) {
    reports.append(Self.report(uuid, update))
    completions.append(completion)
  }

  func reportUpdate(_ uuid: UUID, _ update: CXCallUpdate) {
    updates.append(Self.report(uuid, update))
  }

  func reportEnded(_ uuid: UUID, reason: CXCallEndedReason) {
    ended.append((uuid, reason))
  }

  func reportOutgoingStarted(_ uuid: UUID) {}

  func reportOutgoingConnected(_ uuid: UUID) {}

  func invalidate() {}

  func complete(_ error: (any Error)? = nil) {
    guard !completions.isEmpty else { return }
    completions.removeFirst()(error)
  }

  var waiting: Int { completions.count }

  private static func report(_ uuid: UUID, _ update: CXCallUpdate) -> Report {
    Report(
      uuid: uuid, name: update.localizedCallerName, handle: update.remoteHandle?.value,
      video: update.hasVideo)
  }
}

@MainActor
final class FakeAnswerAction: AnswerActionHandle {
  let actionId = UUID()
  let timeoutDate: Date
  var fulfilled = false
  var failed = false

  init(timeout: TimeInterval = 30) {
    timeoutDate = Date().addingTimeInterval(timeout)
  }

  func fulfill() {
    fulfilled = true
  }

  func fail() {
    failed = true
  }
}

@MainActor
final class RecordingSink: CallEventSink {
  var events: [(String, [String: Any])] = []

  func send(_ method: String, _ arguments: [String: Any]) {
    events.append((method, arguments))
  }

  var methods: [String] { events.map(\.0) }
}

@MainActor
final class CallKitHarness {
  let provider = FakeCallProvider()
  let sink = RecordingSink()
  var ledger: [CallLedgerChange] = []
  var expired: [CallSource] = []
  let center: CallKitCenter

  init(available: Bool = true, resolved: Set<UUID> = [], level: PreviewLevel = .full) {
    let provider = provider
    center = CallKitCenter(
      available: available, makeProvider: { _, _ in provider },
      requestTransaction: { _, _ in })
    center.isResolved = { resolved.contains($0) }
    center.previewLevel = { level }
    center.roomToken = { "t-\($0)" }
    center.onLedger = { [unowned self] in self.ledger.append($0) }
    center.onUnboundAnswerExpired = { [unowned self] in self.expired.append($0) }
    center.attach(sink)
  }

  func attachDart() {
    _ = center.takeEvents()
  }

  func pushRing(
    _ callId: String = "c1", room: String = "!r:zuno.im", name: String = "Alice",
    video: Bool = false, seconds: Int = 49
  ) -> RingAction {
    .ring(
      RingCall(
        uuid: CallIdentity.uuid(roomId: room, callId: callId), roomId: room, callId: callId,
        callerId: "@alice:zuno.im", name: name, video: video, ringSeconds: seconds))
  }
}
