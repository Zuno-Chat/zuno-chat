package im.zuno.chat.zuno_http

import org.chromium.net.CronetException
import org.chromium.net.NetError
import org.chromium.net.NetworkException
import org.chromium.net.QuicException

private const val QUIC_NETWORK_IDLE_TIMEOUT = 25

private val lostConnection = setOf(
    NetError.ERR_NETWORK_CHANGED,
    NetError.ERR_CONNECTION_CLOSED,
    NetError.ERR_CONNECTION_RESET,
    NetError.ERR_CONNECTION_ABORTED,
    NetError.ERR_EMPTY_RESPONSE,
    NetError.ERR_HTTP2_SERVER_REFUSED_STREAM,
    NetError.ERR_HTTP2_PING_FAILED,
    NetError.ERR_CONTENT_LENGTH_MISMATCH,
    NetError.ERR_INCOMPLETE_CHUNKED_ENCODING,
    NetError.ERR_QUIC_GOAWAY_REQUEST_CAN_BE_RETRIED,
)

private val failedConnect = setOf(
    NetError.ERR_CONNECTION_REFUSED,
    NetError.ERR_CONNECTION_FAILED,
    NetError.ERR_ADDRESS_UNREACHABLE,
    NetError.ERR_TUNNEL_CONNECTION_FAILED,
    NetError.ERR_CONNECTION_TIMED_OUT,
    NetError.ERR_SOCKS_CONNECTION_FAILED,
    NetError.ERR_SOCKS_CONNECTION_HOST_UNREACHABLE,
    NetError.ERR_PROXY_CONNECTION_FAILED,
    NetError.ERR_MANDATORY_PROXY_CONFIGURATION_FAILED,
    NetError.ERR_NO_SUPPORTED_PROXIES,
    NetError.ERR_QUIC_HANDSHAKE_FAILED,
)

private val tlsFailures = setOf(
    NetError.ERR_SSL_PROTOCOL_ERROR,
    NetError.ERR_SSL_CLIENT_AUTH_CERT_NEEDED,
    NetError.ERR_SSL_VERSION_OR_CIPHER_MISMATCH,
    NetError.ERR_SSL_RENEGOTIATION_REQUESTED,
    NetError.ERR_BAD_SSL_CLIENT_AUTH_CERT,
    NetError.ERR_SSL_NO_RENEGOTIATION,
    NetError.ERR_SSL_DECOMPRESSION_FAILURE_ALERT,
    NetError.ERR_SSL_BAD_RECORD_MAC_ALERT,
    NetError.ERR_PROXY_CERTIFICATE_INVALID,
    NetError.ERR_SSL_PINNED_KEY_NOT_IN_CERT_CHAIN,
    NetError.ERR_SSL_DECRYPT_ERROR_ALERT,
    NetError.ERR_SSL_SERVER_CERT_CHANGED,
    NetError.ERR_SSL_UNRECOGNIZED_NAME_ALERT,
    NetError.ERR_SSL_SERVER_CERT_BAD_FORMAT,
    NetError.ERR_SSL_OBSOLETE_CIPHER,
    NetError.ERR_TLS13_DOWNGRADE_DETECTED,
    NetError.ERR_SSL_KEY_USAGE_INCOMPATIBLE,
    NetError.ERR_ECH_NOT_NEGOTIATED,
    NetError.ERR_ECH_FALLBACK_CERTIFICATE_INVALID,
)

fun kindOf(internalErrorCode: Int, quicErrorCode: Int): String = when (internalErrorCode) {
    NetError.ERR_ABORTED -> "cancelled"

    NetError.ERR_NAME_NOT_RESOLVED, NetError.ERR_NAME_RESOLUTION_FAILED -> "dns"

    NetError.ERR_INTERNET_DISCONNECTED, NetError.ERR_NETWORK_ACCESS_DENIED -> "offline"

    NetError.ERR_TIMED_OUT -> "timedOut"

    NetError.ERR_CLEARTEXT_NOT_PERMITTED -> "cleartext"

    NetError.ERR_QUIC_PROTOCOL_ERROR ->
        if (quicErrorCode == QUIC_NETWORK_IDLE_TIMEOUT) "connectionLost" else "protocol"

    in lostConnection -> "connectionLost"

    in failedConnect -> "connect"

    in (NetError.ERR_CERT_END + 1)..NetError.ERR_CERT_COMMON_NAME_INVALID, in tlsFailures -> "tls"

    else -> "protocol"
}

internal fun kindOf(error: CronetException): String = when (error) {
    is QuicException -> kindOf(error.cronetInternalErrorCode, error.quicDetailedErrorCode)
    is NetworkException -> kindOf(error.cronetInternalErrorCode, 0)
    else -> "protocol"
}

internal fun detailOf(error: Throwable): String = error.message ?: error.javaClass.simpleName
