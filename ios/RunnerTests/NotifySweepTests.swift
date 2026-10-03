import XCTest

@testable import Runner

@MainActor
final class NotifySweepTests: XCTestCase {
  private func keychain() -> MemoryKeychain {
    let memory = MemoryKeychain()
    memory.store(Data("n".utf8), service: NotifyKeychain.service, account: NotifyKeychain.account)
    memory.store(Data("v".utf8), service: VoipKeyStore.service, account: VoipKeyStore.account)
    memory.store(
      Data("db".utf8), service: "flutter_secure_storage_service",
      account: "matrix_database_cipher")
    return memory
  }

  private func marker() throws -> URL {
    let directory = try makeTemporaryDirectory()
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent(NotifySweep.markerName)
  }

  func testAFreshInstallDropsOnlyTheNotifyAndVoipItemsAndLeavesAMarker() throws {
    let marker = try marker()
    let memory = keychain()

    XCTAssertTrue(NotifySweep.run(marker: marker, backend: memory))

    XCTAssertNil(memory.stored(service: NotifyKeychain.service, account: NotifyKeychain.account))
    XCTAssertNil(memory.stored(service: VoipKeyStore.service, account: VoipKeyStore.account))
    XCTAssertEqual(
      memory.stored(service: "flutter_secure_storage_service", account: "matrix_database_cipher"),
      Data("db".utf8))
    XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
  }

  func testAnInstallThatAlreadySweptKeepsItsItems() throws {
    let marker = try marker()
    let memory = keychain()
    NotifySweep.run(marker: marker, backend: memory)
    memory.store(Data("n2".utf8), service: NotifyKeychain.service, account: NotifyKeychain.account)

    XCTAssertFalse(NotifySweep.run(marker: marker, backend: memory))

    XCTAssertNotNil(memory.stored(service: NotifyKeychain.service, account: NotifyKeychain.account))
  }

  func testAMarkerThatCannotBeReadNeverMeansFresh() throws {
    let marker = try marker()
    let memory = keychain()
    try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)

    XCTAssertFalse(NotifySweep.run(marker: marker, backend: memory))

    XCTAssertNotNil(memory.stored(service: VoipKeyStore.service, account: VoipKeyStore.account))
  }
}
