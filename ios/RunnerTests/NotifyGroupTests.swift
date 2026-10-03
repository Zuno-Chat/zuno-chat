import XCTest

@testable import Runner

final class RunnerInfoPlistTests: XCTestCase {
  private let info = Bundle.main.infoDictionary ?? [:]

  func testTheNotifyGroupIsConfiguredAndResolved() throws {
    let group = try XCTUnwrap(info["ZunoNotifyGroup"] as? String)

    XCTAssertTrue(group.hasPrefix("group.im.zuno.chat.notify."))
    XCTAssertFalse(group.contains("$("))
  }

  func testResearchDataGenerationIsOff() {
    XCTAssertEqual(info["SRResearchDataGeneration"] as? Bool, false)
  }

  func testNoStoryboardBuildsTheFlutterView() throws {
    XCTAssertNil(info["UIMainStoryboardFile"])
    let manifest = try XCTUnwrap(info["UIApplicationSceneManifest"] as? [String: Any])
    let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
    let roles = try XCTUnwrap(
      configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]])
    XCTAssertNil(roles.first?["UISceneStoryboardFile"])
    XCTAssertEqual(roles.first?["UISceneDelegateClassName"] as? String, "Runner.SceneDelegate")
  }
}
