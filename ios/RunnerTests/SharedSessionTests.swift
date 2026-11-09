import XCTest

@testable import zuno_http

final class SharedSessionTests: XCTestCase {
  func testFromIOS26Point6TheNewLoaderRunsWithNothingSentAsEarlyData() throws {
    guard #available(iOS 26.6, *) else { throw XCTSkip("needs iOS 26.6") }
    let configuration = SharedSession.configuration()

    XCTAssertFalse(configuration.usesClassicLoadingMode)
    XCTAssertFalse(configuration.enablesEarlyData)
  }

  func testNoCachesCookiesOrCredentialsAreKept() {
    let configuration = SharedSession.configuration()

    XCTAssertNil(configuration.urlCache)
    XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertNil(configuration.httpCookieStorage)
    XCTAssertFalse(configuration.httpShouldSetCookies)
    XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
    XCTAssertNil(configuration.urlCredentialStorage)
    XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 16)
    XCTAssertEqual(configuration.timeoutIntervalForRequest, unboundedRequestTimeout)
  }
}
