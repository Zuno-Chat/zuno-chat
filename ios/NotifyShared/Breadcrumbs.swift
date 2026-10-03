import Foundation

protocol NseDefaults: Sendable {
  func double(_ key: String) -> Double
  func integer(_ key: String) -> Int
  func crumbs(_ key: String) -> [String: Double]
  func set(_ value: Double, forKey key: String)
  func set(_ value: Int, forKey key: String)
  func setCrumbs(_ value: [String: Double], forKey key: String)
  func remove(_ key: String)
  func keys(withPrefix prefix: String) -> [String]
}

final class Breadcrumbs: Sendable {
  static let crumbsKey = "nse.crumbs"
  static let crashesKey = "nse.crashes"
  static let safeUntilKey = "nse.safe_until"
  static let safeModeSeconds: Double = 3600
  private static let lock = NSLock()

  private let defaults: NseDefaults
  private let processStart: Double

  init(defaults: NseDefaults, processStart: Double) {
    self.defaults = defaults
    self.processStart = processStart
  }

  func begin(_ pushId: String, nowSeconds: Double) -> Bool {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var crumbs = defaults.crumbs(Self.crumbsKey)
    let dead = crumbs.filter { $0.value != processStart }
    if !dead.isEmpty {
      let crashes = defaults.integer(Self.crashesKey) + Set(dead.values).count
      defaults.set(crashes, forKey: Self.crashesKey)
      if crashes >= 2 {
        defaults.set(nowSeconds + Self.safeModeSeconds, forKey: Self.safeUntilKey)
      }
      for key in dead.keys { crumbs.removeValue(forKey: key) }
    }
    crumbs[pushId] = processStart
    defaults.setCrumbs(crumbs, forKey: Self.crumbsKey)
    return nowSeconds < defaults.double(Self.safeUntilKey)
  }

  func end(_ pushId: String) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var crumbs = defaults.crumbs(Self.crumbsKey)
    crumbs.removeValue(forKey: pushId)
    defaults.setCrumbs(crumbs, forKey: Self.crumbsKey)
    defaults.set(0, forKey: Self.crashesKey)
  }
}
