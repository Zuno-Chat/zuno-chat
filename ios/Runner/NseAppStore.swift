import Foundation

struct NseAppStore: Sendable {
  static let marksTakenKey = "zuno.nse.marks_taken"
  static let utdTakenKey = "zuno.nse.utd_taken"
  static let ringsEndedKey = "zuno.nse.rings_ended"

  let state: NseStateStore
  let hashing: NseHashing

  static func current(bundle: Bundle = .main) -> NseAppStore? {
    guard let store = NotifyStore.shared(bundle: bundle),
      let secrets = NseLive.secrets(bundle: bundle)
    else { return nil }
    return NseAppStore(
      state: NseStateStore(files: LiveNseFiles(store: store, key: secrets.readModelKey)),
      hashing: LiveNseHashing(key: secrets.tokenKey))
  }

  func writeShown(_ keys: [String]) {
    state.recordShown(keys.map(hashing.e), in: NotifyFile.shownApp)
  }

  func takeMarks(_ defaults: UserDefaults) -> [[String: Any]] {
    let taken = Int64(defaults.double(forKey: Self.marksTakenKey))
    let (records, pointer) = NseAppLogic.marks(state.marks(), after: taken)
    defaults.set(Double(pointer), forKey: Self.marksTakenKey)
    return records
  }

  func readOutcomes(_ defaults: UserDefaults, counters suite: UserDefaults?, nowMs: Int64)
    -> [[String: Any]]
  {
    let counterDefaults = suite.map(LiveNseDefaults.init)
    var counters: [String: Int] = [:]
    for key in counterDefaults?.keys(withPrefix: NseCounters.prefix) ?? [] {
      counters[key] = counterDefaults?.integer(key)
    }
    let taken = Int64(defaults.double(forKey: Self.utdTakenKey))
    let result = NseAppLogic.outcomes(
      counters: counters, utd: state.state().utd, after: taken,
      generation: hashing.e(NseAppLogic.generationSeed))
    defaults.set(Double(result.pointer), forKey: Self.utdTakenKey)
    for key in NseAppLogic.closedDays(Array(counters.keys), today: NseCounters.day(nowMs)) {
      counterDefaults?.remove(key)
    }
    return result.records
  }

  func roomId(forToken token: String) -> String? {
    state.files.read(NotifyFile.room(token)).flatMap(NseRoomFile.decode)?.room
  }

  static func setCredential(_ credential: String?, expiresMs: Int64?, bundle: Bundle = .main)
    -> Bool
  {
    let keychain = NotifyKeychain(accessGroup: NotifyStore.groupIdentifier(bundle: bundle))
    guard var secrets = NsePipeline.ready(keychain.secrets()) else { return false }
    secrets.credential = credential
    secrets.credentialExpiresTs = credential == nil ? nil : expiresMs
    return keychain.save(secrets)
  }
}

enum NseRoomLookup {
  static let tokenPrefix = "t:"

  static func roomId(_ token: String) -> String? {
    NseAppStore.current()?.roomId(forToken: token)
  }

  static func target(in userInfo: [AnyHashable: Any], resolve: (String) -> String?) -> String? {
    guard let token = userInfo["t"] as? String, isToken(token) else { return nil }
    return resolve(token) ?? tokenPrefix + token
  }

  private static func isToken(_ token: String) -> Bool {
    token.utf8.count == OpaqueIds.length
      && token.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
  }
}
