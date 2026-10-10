import Foundation

@MainActor
final class FakeTimers {
  private final class Entry {
    let milliseconds: Int
    let fire: @MainActor @Sendable () -> Void
    var done = false

    init(milliseconds: Int, fire: @escaping @MainActor @Sendable () -> Void) {
      self.milliseconds = milliseconds
      self.fire = fire
    }
  }

  private var entries: [Entry] = []

  var pendingDelays: [Int] { entries.filter { !$0.done }.map(\.milliseconds) }

  func schedule(
    _ milliseconds: Int, _ fire: @escaping @MainActor @Sendable () -> Void
  ) -> @MainActor () -> Void {
    let entry = Entry(milliseconds: milliseconds, fire: fire)
    entries.append(entry)
    return { entry.done = true }
  }

  func fire(_ index: Int, evenIfCancelled: Bool = false) {
    let entry = entries[index]
    guard evenIfCancelled || !entry.done else { return }
    entry.done = true
    entry.fire()
  }
}

final class Recorder<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Value] = []

  var values: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func add(_ value: Value) {
    lock.lock()
    recorded.append(value)
    lock.unlock()
  }
}

@MainActor
final class FakeBackgroundTasks {
  private var expirations: [Int: @MainActor @Sendable () -> Void] = [:]
  private var next = 0
  private(set) var events: [String] = []
  private(set) var running: [Int] = []
  var refuses = false

  func begin(_ name: String, _ expired: @escaping @MainActor @Sendable () -> Void) -> Int? {
    guard !refuses else { return nil }
    next += 1
    expirations[next] = expired
    running.append(next)
    events.append("begin \(name) #\(next)")
    return next
  }

  func end(_ task: Int) {
    running.removeAll { $0 == task }
    events.append("end #\(task)")
  }

  func expire(_ task: Int) {
    expirations[task]?()
  }
}
