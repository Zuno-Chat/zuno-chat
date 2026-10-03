# iOS push and call ring

**Status: decided 2026-10-01; the app side is built. Owed work is in
`docs/plan-ios-native.md`.**

With Zuno closed, iOS calls ring from a server VoIP push; a running app
still rings from sync. Messages keep `event_id_only` pushes and get their
content from a read-only Notification Service Extension (NSE). Android is
untouched.

- **Ring.** A new Synapse module, `zuno_push`, watches `m.call.member`,
  which is clear state, and sends one sealed, fixed-size VoIP push per
  device through stock Sygnal. It decides with Synapse's own power-level
  and push-rule evaluation, so it rings exactly when Android's closed-app
  ring would: muted rooms stay silent, room creators ring, and a group call
  rings every member. Native code reports every push to CallKit before
  returning; one app-owned Flutter engine then handles answer, decline and
  cancel. `zuno_calls` stays untouched.
- **Why from the server.** The server can tell a call from a message, and
  Apple reserves the NSE ring API for servers that cannot. A server ring
  needs no notification permission, room keys, NSE or filtering
  entitlement, which Apple may refuse.
- **Messages.** The NSE fetches the pushed event with a narrow module
  credential (pushed to this device, unread, recent) and decrypts it with
  Megolm sessions the app exports into a dedicated App Group, trimmed to
  messages the app has not decrypted. It never holds a Matrix token, the
  Olm identity or `zuno.db`. A message it cannot decrypt shows the sender
  and room with "New message", never silence; after a sender's key
  changes, that is what shows until Zuno is opened.
- **Failures surface.** The NSE checks each call invite against the ring
  status; a ring that failed becomes a time-sensitive "Incoming call"
  notification. Rings are sent at least once; the device drops duplicates.
- **Privacy.** For a ring, Apple learns only that a call arrived at a given
  time; message pushes keep the room and event ids stock Sygnal adds. One
  setting, "Name and message" (default), "Name only" or "Nothing", drives
  notification text and the CallKit name. Thread ids and the call handle
  are opaque, there are no Siri donations, notifications are text only,
  and the badge is computed on the device with Sygnal's counts off.

## Rejected

- Ringing from the NSE: it needs an entitlement Apple scopes to servers
  that cannot tell a call, shares the PushKit kill counter, and stops when
  notifications are off.
- The PushKit token as a Matrix pusher: every notifying event would become
  a VoIP push.
- `on_new_event` as the trigger: it loads full room state for every event
  on every worker, before sync and pushers wake.
- Sharing `zuno.db` with the NSE: lock kills in the background, and every
  key within the NSE's reach.
- A Matrix token in the NSE: tokens are short-lived, and a second refresher
  logs the app out.
- A plaintext VoIP payload: it hands Apple the room, the call and the
  video flag.
- A to-device key peek, full or reduced: it would put copies of the
  phone's Olm channels, or its device identity, in the process most
  exposed to hostile input. Names only after a key change is accepted.
- Background refresh to fetch keys: it runs near the user's own app opens
  and never after a force-quit.
- A custom push gateway or relay: Sygnal stays stock.
