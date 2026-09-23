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
| `map_tiles.dart` | `fetchTileSource` (the `im.zuno.tiles` well-known entry → `TileSource`, `null` when absent or unusable), `probeMapTiles`. |
| `map_tiles_provider.dart`, `map_tile_cache.dart` | `mapTilesProvider` (`FutureProvider<MapTiles?>`: source + plain client + tile provider, `null` until a probe succeeds, retried every 5 min while `null`), `purgeMapTileCache()`. |
| `lib/features/location/presentation/` | `location_share_sheet.dart` (find → preview → send), `location_bubble.dart`, `location_map_page.dart` (full screen + Open in Maps), `location_map_view.dart` (flutter_map or grid fallback; the source's attribution on the interactive map only, top-right and muted — previews carry none). |

### Data flow

Attach sheet → "Location" (always offered, like photos and files, even when
nobody else is in the chat) → the sheet finds a fix → `room.sendEvent(
locationMessageContent(...))`. An ordinary encrypted, redactable message;
nothing is uploaded. Receiving: `summarize()` returns `MessageKind.location`
/ "Location" for every `m.location`, malformed ones included; the bubble
renders a mini map (or the fallback) and tap opens `LocationMapPage`.

Tiles: the server name's `/.well-known/matrix/client` (via
`client.getWellknown`, read fresh on every provider run, no SDK cache)
names the source; the app fetches `{z}/{x}/{y}` straight from it, no
auth header, the key riding in the template's query, sent with the app
User-Agent (the provider's header overrides flutter_map's own). Probe: the template
at `0/0/0`, `200` + `image/*`. Cached by flutter_map's built-in cache
(hashed filenames, 64 MB cap, honours `Cache-Control`/`ETag`), purged at
logout, account deletion, and "Clear media cache".
The layer runs with `panBuffer: 0` and flutter_map's default
abort-on-obsolete, so a pan fetches only what is visible and cancels what
scrolled out.

### Decisions

- **The homeserver names the tile source, the app holds no key.** A key
  rotation or style change is a well-known edit, not a release, and
  someone on another homeserver never spends Zuno's quota. The key is
  public by nature (every device sees it); restrict it at MapTiler.
- **Well-known read fresh, not the SDK's 3-day cache**, whenever the
  provider builds: first map shown per process, login/logout, and every
  5 minutes while it has no usable tiles. One small GET, only once a map
  is shown.
- **Degrade, never fail.** No source (probe ≠ 200 `image/*`) → grid + pin +
  coordinates + Open in Maps. The pin shipped before any server work.
- **`flutter_map` over `google_maps_flutter`** — no Play Services.
  **`geolocator` owns location**; `permission_handler` stays with camera/mic.
- **No thumbnail on the event**; the bubble renders its own map. No place
  search, no view receipts, no geofences (spec §0).
- **Coarse-only grants still send, labelled approximate**; `u=` carries the
  accuracy either way.
- **The full map is fenced: zoom floor 12, a ~10 km-each-way box around
  the pin** (`CameraConstraint.contain`, so the whole view stays inside,
  which also stops world wrap). Previews are static and unfenced. Bounds
  every session's tile spend; on a wide screen the box stops zoom-out
  before level 12.
- **No tile preload beyond the viewport (`panBuffer: 0`).** Every tile
  miss is a billed request against the source's quota; edges filling in
  during a pan is the accepted trade.
- **Attribution lives on the full-screen map, not on previews.** A bar on
  every thumbnail read as a black footer in dark mode; one tap from any
  pin keeps the credit visible without that. No `attribution` in the
  entry, no bar.

### Server contract (outside this repo)

`/.well-known/matrix/client` on the server name carries
`"im.zuno.tiles": {"url": "https://…/{z}/{x}/{y}.png?key=…",
"attribution": "…"}`. `url` must be `https` with all three placeholders,
else the map falls back to the grid; 256 px raster tiles, zoom up to 19.
`attribution` is optional and shown after flutter_map's own
`flutter_map | © ` prefix, so it must not start with `©`. zuno.chat's
lives in `zuno_web/src/.well-known/matrix/client` (MapTiler).

### Gotchas

- **A tile cache is a location history** in plain files. Keep the cap and
  every purge site.
- **`geo:` intents need a `<queries>` entry** (Android 11+) or `launchUrl`
  reports no handler.
- **The preview map sits inside an `IgnorePointer`**, so the bubble's
  `GestureDetector` must be `HitTestBehavior.opaque`; a deferring detector
  never sees the tap once tiles render (the grid fallback only worked
  because its pin icon was hittable).
- **The probe result is per process.** A newly added or fixed source
  shows up on the next launch or within 5 minutes; but once tiles work,
  nothing re-reads the well-known, so a revoked key leaves grey tiles
  (not the grid) until the process restarts. Rotate by keeping the old
  key alive for a while.
- **The tile URL is the well-known's, key included**, so it is in every
  tile request and in the cache's (hashed) keys. A new key misses the
  whole cache once.
- No widget test renders real tiles. Bubble and sheet are tested in the
  degraded path with `mapTilesProvider` overridden.

## Live beacon — designed, not built

Three channels (state presence `im.zuno.location_beacon`, Olm to-device
`im.zuno.location_ping`, two timeline tiles), two independent clocks
(`planned_until_ts` vs the `expires_ts` liveness TTL), no
`ACCESS_BACKGROUND_LOCATION`, fixed durations only. See the spec §2, §4–§6
and its build order (phases 3–5). Adds `MessageKind.locationShare` and
permission #16 when built.
