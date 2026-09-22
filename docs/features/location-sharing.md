# Location Sharing

Two halves that are architecturally opposite. The **pin** (a one-off
`m.location` message) is built. The **live beacon** (ephemeral shared state
with a hard expiry) is designed only, in notes kept outside the repo; nothing
below describes it as shipped.

## Pin — built

### Components

| Piece (`lib/core/location/`) | Role |
|---|---|
| `geo_uri.dart` | Parse/format `geo:lat,lon;u=m` (RFC 5870). Malformed input → `null`, never a throw. |
| `location_message.dart` | Builds MSC3488 content (`msgtype: m.location`, `geo_uri`, `org.matrix.msc3488.*`). `locationOf(event)` reads a pin from any client, falling back to the MSC3488 block when `geo_uri` is absent. |
| `current_position.dart` | `findCurrentLocation()` → `LocationFound(geo, approximate)` or `LocationFailed(servicesOff / denied / deniedForever / unavailable)`. Takes a `GeolocatorPlatform` for tests. |
| `map_tiles.dart` | `mapTilesBaseUri` (`https://{homeserver-host}/tiles`, `null` when unset), `MapTilesHttpClient` (gateway bearer, one retry on 401), `probeMapTiles`. |
| `map_tiles_provider.dart`, `map_tile_cache.dart` | `mapTilesProvider` (one authed client + tile provider per login), `mapTilesAvailableProvider` (session probe, retried every 5 min while false), `purgeMapTileCache()`. |
| `lib/features/location/presentation/` | `location_share_sheet.dart` (find → preview → send), `location_bubble.dart`, `location_map_page.dart` (full screen + Open in Maps), `location_map_view.dart` (flutter_map or grid fallback; OSM attribution on the interactive map only, top-right and muted — previews carry none). |

### Data flow

Attach sheet → "Location" (always offered, like photos and files, even when
nobody else is in the chat) → the sheet finds a fix → `room.sendEvent(
locationMessageContent(...))`. An ordinary encrypted, redactable message;
nothing is uploaded. Receiving: `summarize()` returns `MessageKind.location`
/ "Location" for every `m.location`, malformed ones included; the bubble
renders a mini map (or the fallback) and tap opens `LocationMapPage`.

Tiles: `GET {homeserver-host}/tiles/{z}/{x}/{y}.png` with
`Authorization: Bearer <gateway per-device token>` — the `POST /calls/enroll`
token, the same auth as `/calls/*`. Cached by flutter_map's built-in cache
(hashed filenames, 64 MB cap, honours `Cache-Control`/`ETag`), purged at
logout, account deletion, and "Clear media cache".
The layer runs with `panBuffer: 0` and flutter_map's default
abort-on-obsolete, so a pan fetches only what is visible and cancels what
scrolled out; `MapTilesHttpClient`'s 401 retry rebuilds the request as an
`AbortableRequest` so that cancellation survives a token refresh.

### Decisions

- **Gateway token, not the Matrix access token, for tiles.** The design spec
  predates `docs/decisions/calls-gateway-enrollment.md`; its reason (a
  gateway breach must not be an account breach) applies to every route.
- **Degrade, never fail.** No proxy (probe ≠ 200 `image/*`) → grid + pin +
  coordinates + Open in Maps. The pin shipped before any server work.
- **`flutter_map` over `google_maps_flutter`** — no Play Services.
  **`geolocator` owns location**; `permission_handler` stays with camera/mic.
- **No thumbnail on the event**; the bubble renders its own map. No place
  search, no view receipts, no geofences (spec §0).
- **Coarse-only grants still send, labelled approximate**; `u=` carries the
  accuracy either way.
- **No tile preload beyond the viewport (`panBuffer: 0`).** Every tile
  costs the gateway a proxied fetch under a per-device rate limit; edges
  filling in during a pan is the accepted trade.
- **Attribution lives on the full-screen map, not on previews.** A bar on
  every thumbnail read as a black footer in dark mode; one tap from any
  pin keeps the OSM credit visible without that.

### Gateway contract (server side, outside this repo)

Route `/tiles/{z}/{x}/{y}.png`; validate `z` 0..19 and `x`, `y` in range;
gateway bearer, 401 on unknown/expired; proxy to an OSM raster source with
the gateway's own `User-Agent`, no client IP forwarded, server-side cache;
respond `image/png` + `ETag` + `Cache-Control: max-age`; rate-limit per
device (a map view fetches ~15–30 tiles). Probe URL: `/tiles/0/0/0.png`.

### Gotchas

- **A tile cache is a location history** in plain files. Keep the cap and
  every purge site.
- **`geo:` intents need a `<queries>` entry** (Android 11+) or `launchUrl`
  reports no handler.
- **The preview map sits inside an `IgnorePointer`**, so the bubble's
  `GestureDetector` must be `HitTestBehavior.opaque`; a deferring detector
  never sees the tap once tiles render (the grid fallback only worked
  because its pin icon was hittable).
- **The probe result is per session**; a newly deployed proxy shows up on
  the next launch or within 5 minutes.
- No widget test renders real tiles. Bubble and sheet are tested in the
  degraded path with `mapTilesProvider`/`mapTilesAvailableProvider`
  overridden.

## Live beacon — designed, not built

Three channels (state presence `im.zuno.location_beacon`, Olm to-device
`im.zuno.location_ping`, two timeline tiles), two independent clocks
(`planned_until_ts` vs the `expires_ts` liveness TTL), no
`ACCESS_BACKGROUND_LOCATION`, fixed durations only. See the spec §2, §4–§6
and its build order (phases 3–5). Adds `MessageKind.locationShare` and
permission #16 when built.
