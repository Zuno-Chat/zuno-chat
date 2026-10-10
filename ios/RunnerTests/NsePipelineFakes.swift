import Foundation

@testable import Runner

struct NseFakeHashing: NseHashing {
  func t(_ roomId: String) -> String { "t\(roomId)" }
  func e(_ value: String) -> String { "e\(value)" }
  func rg(_ callUuid: UUID) -> String { "rg\(callUuid.uuidString)" }
}

struct NseFakeKeychain: NseKeychainReading {
  let result: NotifySecretsRead

  func secrets() -> NotifySecretsRead { result }
}

final class NseFakeCenter: NseDeliveredCenter, @unchecked Sendable {
  private let lock = NSLock()
  private var notes: [NseDelivered]

  init(_ notes: [NseDelivered] = []) {
    self.notes = notes
  }

  func delivered() async -> [NseDelivered] {
    current()
  }

  private func current() -> [NseDelivered] {
    lock.lock()
    defer { lock.unlock() }
    return notes
  }
}

final class NseFakeSignals: NseSignals, @unchecked Sendable {
  private let lock = NSLock()
  private var postedNames: [String] = []
  private var loggedLines: [String] = []

  var posted: [String] {
    lock.lock()
    defer { lock.unlock() }
    return postedNames
  }

  var logged: [String] {
    lock.lock()
    defer { lock.unlock() }
    return loggedLines
  }

  func post(_ hint: DarwinHint) {
    lock.lock()
    postedNames.append(hint.rawValue)
    lock.unlock()
  }

  func log(_ event: String, _ fields: [(String, String)]) {
    lock.lock()
    loggedLines.append(([event] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " "))
    lock.unlock()
  }
}

final class NseFakeDecryptor: MegolmDecrypting, @unchecked Sendable {
  private let lock = NSLock()
  private let plaintexts: [String: String]
  private var count = 0

  init(_ plaintexts: [String: String] = [:]) {
    self.plaintexts = plaintexts
  }

  var calls: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func decrypt(pickle: String, userId: String, ciphertext: String) -> MegolmDecryptOutcome {
    lock.lock()
    count += 1
    lock.unlock()
    return plaintexts[ciphertext].map { .plaintext($0) } ?? .failed
  }
}

struct NseHarness {
  let files = NseFakeFiles()
  let clock = NseFakeClock(now: NseTestData.now)
  let transport: NseFakeTransport
  let center: NseFakeCenter
  let defaults = NseFakeDefaults()
  let signals = NseFakeSignals()
  let decryptor: NseFakeDecryptor
  let keychain: NotifySecretsRead
  let best = Recorder<NseDelivery>()

  init(
    keychain: NotifySecretsRead = .ready(NseTestData.keys), delivered: [NseDelivered] = [],
    plaintexts: [String: String] = [:]
  ) {
    self.keychain = keychain
    transport = NseFakeTransport(clock: clock)
    center = NseFakeCenter(delivered)
    decryptor = NseFakeDecryptor(plaintexts)
  }

  var environment: NseEnvironment {
    let files = self.files
    return NseEnvironment(
      keychain: NseFakeKeychain(result: keychain), files: { _ in files },
      hashing: { _ in NseFakeHashing() }, transport: transport, decryptor: decryptor,
      center: center, clock: clock, defaults: defaults, signals: signals, processStart: 100,
      footprint: { 8_000_000 }, version: "2.1 (40)")
  }

  func run(_ push: NsePush = NseTestData.push()) async -> NseResult {
    let best = self.best
    return await NsePipeline(env: environment).run(push) { best.add($0) }
  }
}
