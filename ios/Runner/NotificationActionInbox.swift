import Foundation

@MainActor
final class NotificationActionInbox {
  typealias NotSent =
    @MainActor (NotificationActionNotice, @escaping @MainActor @Sendable () -> Void) -> Void
  typealias MarkedRead = @MainActor (NotificationActionRequest) -> Void

  static let timeoutMs = 25_000

  private struct Pending {
    let request: NotificationActionRequest
    let task: Int?
    let cancelTimeout: @MainActor () -> Void
    let complete: @MainActor @Sendable () -> Void
    var taken = false
  }

  var onAccepted: (@MainActor () -> Void)?
  private let begin: WakeLockLedger.Begin
  private let end: WakeLockLedger.End
  private let schedule: WakeLockLedger.Schedule
  private let notSent: NotSent
  private let markedRead: MarkedRead
  private var pending: [String: Pending] = [:]
  private var order: [String] = []

  init(
    begin: @escaping WakeLockLedger.Begin, end: @escaping WakeLockLedger.End,
    schedule: @escaping WakeLockLedger.Schedule, notSent: @escaping NotSent,
    markedRead: @escaping MarkedRead
  ) {
    self.begin = begin
    self.end = end
    self.schedule = schedule
    self.notSent = notSent
    self.markedRead = markedRead
  }

  var pendingIds: [String] { order }

  func accept(
    _ request: NotificationActionRequest, complete: @escaping @MainActor @Sendable () -> Void
  ) {
    let id = request.id
    guard pending[id] == nil else {
      complete()
      return
    }
    let task = begin("zuno:notification_action") { [weak self] in
      self?.settle(id, ok: false, expiring: true)
    }
    let cancelTimeout = schedule(Self.timeoutMs) { [weak self] in
      self?.settle(id, ok: false, expiring: false)
    }
    pending[id] = Pending(
      request: request, task: task, cancelTimeout: cancelTimeout, complete: complete)
    order.append(id)
    onAccepted?()
  }

  func take() -> [NotificationActionRequest] {
    var handed: [NotificationActionRequest] = []
    for id in order {
      guard var entry = pending[id], !entry.taken else { continue }
      entry.taken = true
      pending[id] = entry
      handed.append(entry.request)
    }
    return handed
  }

  func finish(_ id: String, ok: Bool) {
    settle(id, ok: ok, expiring: false)
  }

  private func settle(_ id: String, ok: Bool, expiring: Bool) {
    guard let entry = pending.removeValue(forKey: id) else { return }
    order.removeAll { $0 == id }
    entry.cancelTimeout()
    if expiring, let task = entry.task {
      end(task)
    }
    let remaining = expiring ? nil : entry.task
    let complete = entry.complete
    let done: @MainActor @Sendable () -> Void = { [weak self] in
      complete()
      if let remaining { self?.end(remaining) }
    }
    switch (ok, entry.request.kind) {
    case (false, .reply):
      notSent(entry.request.notice, done)
    case (true, .markRead):
      markedRead(entry.request)
      done()
    default:
      done()
    }
  }
}
