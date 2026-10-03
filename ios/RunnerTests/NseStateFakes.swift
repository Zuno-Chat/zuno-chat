import Foundation

@testable import Runner

final class NseFakeFiles: NseFiles, @unchecked Sendable {
  private let lock = NSLock()
  private var contents: [String: Data] = [:]
  private var counts: [String: Int] = [:]

  func read(_ name: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return contents[name]
  }

  func write(_ name: String, _ data: Data) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    contents[name] = data
    counts[name, default: 0] += 1
    return true
  }

  func writes(_ name: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return counts[name] ?? 0
  }

  func put(_ name: String, _ object: [String: Any]) {
    _ = write(name, (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
  }

  func json(_ name: String) -> NseJson? {
    read(name).flatMap(NseJson.parse)
  }
}

final class NseFakeDefaults: NseDefaults, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Any] = [:]

  func double(_ key: String) -> Double {
    lock.lock()
    defer { lock.unlock() }
    return values[key] as? Double ?? 0
  }

  func integer(_ key: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return values[key] as? Int ?? 0
  }

  func crumbs(_ key: String) -> [String: Double] {
    lock.lock()
    defer { lock.unlock() }
    return values[key] as? [String: Double] ?? [:]
  }

  func set(_ value: Double, forKey key: String) { store(value, key) }
  func set(_ value: Int, forKey key: String) { store(value, key) }
  func setCrumbs(_ value: [String: Double], forKey key: String) { store(value, key) }

  func remove(_ key: String) {
    lock.lock()
    values.removeValue(forKey: key)
    lock.unlock()
  }

  func keys(withPrefix prefix: String) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return values.keys.filter { $0.hasPrefix(prefix) }.sorted()
  }

  private func store(_ value: Any, _ key: String) {
    lock.lock()
    values[key] = value
    lock.unlock()
  }
}
