import CryptoKit
import Foundation

@MainActor
final class ReadModelCache {
  struct SecretsUnavailable: Error {}

  static let shared = ReadModelCache(
    store: NotifyStore.shared(),
    keychain: NotifyKeychain(accessGroup: NotifyStore.groupIdentifier()))

  private let store: NotifyStore?
  private let keychain: NotifyKeychain
  private let now: @MainActor () -> Int64
  private var secretsCache: NotifySecrets?
  private var metaCache: NotifyMeta??
  private var ledgerCache: Ledger?
  private var rooms: [String: RoomTitleFile?] = [:]

  init(
    store: NotifyStore?, keychain: NotifyKeychain,
    now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.store = store
    self.keychain = keychain
    self.now = now
  }

  var log: DeliveryLog? {
    store.map { DeliveryLog(url: $0.url(NotifyFile.appLog)) }
  }

  func secrets(create: Bool) -> NotifySecretsRead {
    if let secretsCache { return .ready(secretsCache) }
    guard let store else { return .unavailable }
    let read = keychain.load(createIfMissing: create)
    switch read {
    case .ready(let secrets):
      Self.prepare(store)
      secretsCache = secrets
    case .created(let secrets):
      Self.prepare(store)
      store.wipe()
      forgetFiles()
      secretsCache = secrets
    case .locked, .unavailable:
      break
    }
    return read
  }

  func meta() -> NotifyMeta? {
    if let metaCache { return metaCache }
    guard let store, let secrets = readySecrets() else { return nil }
    var meta: NotifyMeta?
    if case .found(let data) = store.read(NotifyFile.meta, key: secrets.readModelKey) {
      meta = NotifyMeta.decoded(data, reporting: "notify meta decode")
    }
    metaCache = .some(meta)
    return meta
  }

  func roomToken(_ roomId: String) -> String? {
    readySecrets().map { OpaqueIds.roomToken(roomId, installKey: $0.tokenKey) }
  }

  func room(_ roomId: String) -> RoomTitleFile? {
    if let cached = rooms[roomId] { return cached }
    guard let store, let secrets = readySecrets() else { return nil }
    let name = NotifyFile.room(OpaqueIds.roomToken(roomId, installKey: secrets.tokenKey))
    var file: RoomTitleFile?
    if case .found(let data) = store.read(name, key: secrets.readModelKey) {
      file = RoomTitleFile.decoded(data, roomId: roomId, reporting: "room title decode")
    }
    rooms[roomId] = .some(file)
    return file
  }

  func ledger() -> Ledger {
    if let ledgerCache { return ledgerCache }
    guard let store, let secrets = readySecrets() else { return Ledger() }
    var ledger = Ledger()
    if case .found(let data) = store.read(NotifyFile.ledger, key: secrets.readModelKey),
      let decoded = Ledger.decoded(data)
    {
      ledger = decoded
    }
    ledgerCache = ledger
    return ledger
  }

  func record(_ change: CallLedgerChange) {
    guard let store, let secrets = readySecrets() else { return }
    var ledger = ledger()
    ledger.record(
      uuid: change.identity,
      roomToken: OpaqueIds.roomToken(change.roomId, installKey: secrets.tokenKey),
      state: change.state, source: change.source, at: now())
    ledgerCache = ledger
    CaughtErrors.attempt("ledger write") {
      try store.write(NotifyFile.ledger, plaintext: ledger.encoded(), key: secrets.readModelKey)
    }
    DarwinHint.ringChanged.post()
  }

  func writeMeta(_ json: Data) throws {
    guard let store else { throw CocoaError(.fileWriteUnknown) }
    guard let secrets = writableSecrets() else { throw SecretsUnavailable() }
    guard let meta = NotifyMeta.decoded(json) else { throw CocoaError(.coderReadCorrupt) }
    if try store.writeIfChanged(NotifyFile.meta, plaintext: json, key: secrets.readModelKey) {
      DarwinHint.readModelChanged.post()
    }
    try store.writeRingFlag(meta.ringtone)
    metaCache = .some(meta)
  }

  func writeRoom(roomId: String, json: Data) throws {
    guard let store else { throw CocoaError(.fileWriteUnknown) }
    guard let secrets = writableSecrets() else { throw SecretsUnavailable() }
    guard let file = RoomTitleFile.decoded(json, roomId: roomId) else {
      throw CocoaError(.coderReadCorrupt)
    }
    let name = NotifyFile.room(OpaqueIds.roomToken(roomId, installKey: secrets.tokenKey))
    if try store.writeIfChanged(name, plaintext: json, key: secrets.readModelKey) {
      DarwinHint.readModelChanged.post()
    }
    rooms[roomId] = .some(file)
  }

  func deleteRoom(roomId: String) {
    guard let store, let secrets = readySecrets() else { return }
    store.remove(NotifyFile.room(OpaqueIds.roomToken(roomId, installKey: secrets.tokenKey)))
    rooms[roomId] = .some(nil)
    DarwinHint.readModelChanged.post()
  }

  func threadKey(roomId: String) -> String? {
    writableSecrets().map { OpaqueIds.roomToken(roomId, installKey: $0.tokenKey) }
  }

  func wipe() {
    store?.wipe()
    keychain.delete()
    secretsCache = nil
    forgetFiles()
    DarwinHint.readModelChanged.post()
  }

  func signedOut() -> MarkerRead {
    store?.signedOut() ?? .absent
  }

  func setSignedOut(_ signedOut: Bool) {
    guard let store else { return }
    Self.prepare(store)
    if signedOut {
      CaughtErrors.attempt("signed out mark") { try store.markSignedOut() }
    } else {
      store.clearSignedOut()
    }
  }

  func ringFlag() -> Bool? {
    store?.readRingFlag()
  }

  private func readySecrets() -> NotifySecrets? {
    if case .ready(let secrets) = secrets(create: false) { return secrets }
    return secretsCache
  }

  private func writableSecrets() -> NotifySecrets? {
    switch secrets(create: true) {
    case .ready(let secrets), .created(let secrets): return secrets
    case .locked, .unavailable: return nil
    }
  }

  private static func prepare(_ store: NotifyStore) {
    CaughtErrors.attempt("read model prepare") { try store.prepare() }
  }

  private func forgetFiles() {
    metaCache = nil
    ledgerCache = nil
    rooms = [:]
  }
}
