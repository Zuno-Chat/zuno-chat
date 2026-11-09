import Foundation

func failureKind(of error: Error) -> String {
  let nsError = error as NSError
  if nsError.domain == NSPOSIXErrorDomain {
    switch POSIXErrorCode(rawValue: Int32(nsError.code)) {
    case .ENETDOWN, .ENETUNREACH: return "offline"
    case .ECONNREFUSED, .EHOSTUNREACH: return "connect"
    case .EPIPE, .ECONNABORTED, .ECONNRESET, .ENOTCONN, .ETIMEDOUT: return "connectionLost"
    default: return "protocol"
    }
  }
  guard nsError.domain == NSURLErrorDomain else { return "protocol" }
  switch nsError.code {
  case NSURLErrorCancelled: return "cancelled"
  case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed,
    NSURLErrorInternationalRoamingOff:
    return "offline"
  case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "dns"
  case NSURLErrorCannotConnectToHost: return "connect"
  case NSURLErrorTimedOut: return "timedOut"
  case NSURLErrorNetworkConnectionLost, NSURLErrorCallIsActive,
    NSURLErrorRequestBodyStreamExhausted:
    return "connectionLost"
  case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "cleartext"
  case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
    NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
    NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
    NSURLErrorClientCertificateRequired:
    return "tls"
  default: return "protocol"
  }
}

func failureDetail(of error: Error) -> String {
  let nsError = error as NSError
  let cause = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map {
    " (\($0.domain) \($0.code))"
  }
  return "\(nsError.domain) \(nsError.code)\(cause ?? "")"
}
