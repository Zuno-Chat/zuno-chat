import Foundation

enum PushEnvironment: String, Equatable, Sendable {
  case production
  case development

  static let current = resolve(
    profile: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
      .flatMap(profileData),
    simulator: runsOnSimulator)

  private static func profileData(_ url: URL) -> Data? {
    CaughtErrors.attempt("push environment profile") { try Data(contentsOf: url) }
  }

  static func resolve(profile: Data?, simulator: Bool) -> PushEnvironment {
    if simulator { return .development }
    guard let profile, let entitlements = entitlements(in: profile) else { return .production }
    return entitlements["aps-environment"] as? String == "development" ? .development : .production
  }

  static func entitlements(in profile: Data) -> [String: Any]? {
    guard let start = profile.range(of: Data("<?xml".utf8)),
      let end = profile.range(
        of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex)
    else { return nil }
    let plist = profile.subdata(in: start.lowerBound..<end.upperBound)
    let object = CaughtErrors.attempt("push environment plist") {
      try PropertyListSerialization.propertyList(from: plist, format: nil)
    }
    guard let dictionary = object as? [String: Any] else { return nil }
    return dictionary["Entitlements"] as? [String: Any]
  }

  private static var runsOnSimulator: Bool {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }
}
