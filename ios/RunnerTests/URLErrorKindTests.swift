import XCTest

@testable import zuno_http

final class URLErrorKindTests: XCTestCase {
  func testErrorsMapToTheirKind() {
    let cases: [(Error, String)] = [
      (URLError(.cancelled), "cancelled"),
      (URLError(.notConnectedToInternet), "offline"),
      (URLError(.dataNotAllowed), "offline"),
      (URLError(.cannotFindHost), "dns"),
      (URLError(.cannotConnectToHost), "connect"),
      (URLError(.timedOut), "timedOut"),
      (URLError(.networkConnectionLost), "connectionLost"),
      (URLError(.appTransportSecurityRequiresSecureConnection), "cleartext"),
      (URLError(.serverCertificateUntrusted), "tls"),
      (URLError(.badServerResponse), "protocol"),
      (POSIXError(.ECONNRESET), "connectionLost"),
      (POSIXError(.ENETDOWN), "offline"),
      (POSIXError(.ECONNREFUSED), "connect"),
      (NSError(domain: "other", code: 1), "protocol"),
    ]

    XCTAssertEqual(cases.map { failureKind(of: $0.0) }, cases.map(\.1))
  }

  func testTheDetailNamesTheErrorAndItsCauseWithoutTheirTranslatedText() {
    let cause = NSError(domain: "kCFErrorDomainCFNetwork", code: -1202)
    let error = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Das Zertifikat für diesen Server ist ungültig: „matrix.example.org“",
        NSUnderlyingErrorKey: cause,
      ])

    XCTAssertEqual(
      failureDetail(of: error), "NSURLErrorDomain -1202 (kCFErrorDomainCFNetwork -1202)")
  }

  func testTheDetailOfAnErrorWithNoCauseIsItsDomainAndCode() {
    XCTAssertEqual(failureDetail(of: URLError(.timedOut)), "NSURLErrorDomain -1001")
  }
}
