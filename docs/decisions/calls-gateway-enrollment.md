# Gateway enrollment

Decision: the app authenticates to the Go gateway with a gateway-issued
per-device token, crossing the Matrix access token to the gateway once per
device, at enrollment, never per request. Calls no longer use it: they go to
the `zuno_calls` Synapse module with the Matrix access token, which Synapse
itself checks on every request. Map tiles are the only enrolled route left.

Why: per-request Matrix bearers make a gateway breach an account breach;
enrollment limits it to what the gateway serves. No OpenID here, so a
gateway-minted credential is the verifiable alternative, and local hash
lookup drops a whoami round trip per request.

Contract:
- `POST /calls/enroll`, `Bearer <matrix access token>`, body
  `{"device_id"}`. Gateway calls whoami, requires `device_id` to match,
  replaces any token for (user, device), stores SHA-256(token), returns
  `{"token","expires_at"}` (ms). TTL fixed from issue (gateway config), no
  sliding on use, rate-limited per user.
- Every `/tiles/*` request: `Bearer <gateway token>`. Unknown or expired:
  401. App re-enrolls once and retries.
- `DELETE /calls/enroll`, `Bearer <gateway token>`: revoke. Called at
  logout and account deletion, best effort. A remote logout cannot revoke
  it; the fixed expiry bounds that exposure.

Client: `GatewayCredentials` (`lib/core/matrix/`), `flutter_secure_storage`
key `calls_gateway_token:<userId>:<deviceId>` (name kept from when calls
used it, so devices don't re-enroll), JSON `{token, expires_at}`, expired
1 minute early, concurrent callers share one enrollment.
