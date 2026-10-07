# iOS push and call ring

With Zuno closed, an iOS call rings from a server-sent VoIP push; a running app still rings from sync. Messages keep `event_id_only` alert pushes, and a read-only notification service extension (NSE) fetches and decrypts their content. Android is untouched by all of this. The mechanics are in `../features/notifications.md` (push, the extension, the `zuno_push` contract) and `../features/calls.md` (the ring).

- **Ring from the server.** Apple tells servers that can tell a call from a message to send a VoIP push, and reserves the NSE ring API (behind the filtering entitlement) for servers that cannot. Zuno's server can: the `zuno_push` Synapse module watches `m.call.member`, which is clear state, and sends through stock Sygnal. A server ring needs no notification permission, room keys, NSE or entitlement, so nothing depends on an entitlement Apple may refuse.
- **Ring parity with Android.** The module decides with Synapse's own power-level and push-rule evaluation, so a closed iPhone rings exactly when Android's closed-app ring would: muted rooms stay silent, room creators ring, and a group call rings every member. A hand-written check would drift: a raw power-level read misses room-v12 creators, which includes every new Zuno DM, and hand-picked mute rules miss settings changed in other clients.
- **Rings are sent at least once.** The module re-sends a ring that a crash interrupted, and the device drops duplicates by the call's UUID.
- **A sealed, fixed-size VoIP payload under a per-device key.** Apple learns only that a call arrived at a given time. The key id and expiry stay in clear as associated data, so the device can drop a stale ring even before first unlock. A key mismatch rings generically instead of silently.
- **A fetching, read-only NSE.** It fetches the pushed event with a narrow module credential (an event that notified this user, still unread and recent) and decrypts it with Megolm sessions the app exports, trimmed to recent messages. Those sessions sit in a dedicated App Group that only the app and the NSE share. The NSE never holds a Matrix token, the Olm identity or `zuno.db`.
- **Names, never silence.** A message the NSE cannot decrypt shows its sender and room with "New message"; after a sender's key changes, that is what shows until Zuno is opened. A reply that did not come from the module (a misrouted proxy) also shows names, loudly. A call whose ring failed becomes a time-sensitive fallback notification.
- **Private by default.** One preview level drives notification text and the CallKit name, because the OS keeps what a notification showed. Thread ids and the call handle are opaque, and there are no Siri donations. Notifications are text only, since images would add a zero-click attack surface. The badge is computed on the device. Message pushes still show Apple the room and event ids that stock Sygnal adds.
- **Constraint.** The ring depends on `m.call.member` staying clear state. Encrypted or sticky call membership would hide the trigger and need an explicit ring endpoint.

## Accepted costs

- Calls ring even when notifications are denied: calls are not notifications, and PushKit needs no permission.
- At preview Nothing the NSE fetches nothing, so a failed ring gets no fallback, and an invitation's alert tone may sound before the ring. Holding DM pushes to avoid that would delay every message.
- A room read elsewhere while Zuno is closed keeps its badge until the next push's catch-up or the next open, because receipt badge pushes are off.
- An app not opened for 30 days has an expired credential, so its notifications show names only until the next open.

## Rejected

- **Ringing from the NSE.** The entitlement is scoped to servers that cannot tell a call, the API shares PushKit's kill counter, and an NSE does not run while notifications are off.
- **The PushKit token as a Matrix pusher.** Every notifying event would become a VoIP push, and iOS requires each VoIP push to report a call.
- **`on_new_event` as the trigger.** Registering it makes Synapse load full room state for every event on every worker, before sync and pushers wake.
- **`zuno.db` in the NSE.** A file lock held at suspension gets the process killed, and every key would be within the NSE's reach.
- **A Matrix token in the NSE.** Tokens are short-lived, a second refresher logs the app out, and longer token lifetimes would change Android too.
- **Dart or the full SDK in the NSE.** They do not fit the extension's memory limit.
- **A plaintext VoIP payload.** It hands Apple the room, the call and the video flag. A fully sealed blob, with no clear key id or expiry, could not be checked for staleness before first unlock.
- **A to-device key peek, full or reduced.** It would put copies of the phone's Olm channels, or its device identity, in the process most exposed to hostile input. Names only after a key change is accepted instead.
- **The NSE as its own Matrix device.** Every sender would have to share keys with one more device per user.
- **Background refresh to fetch keys.** It runs near the user's own app opens and never after a force-quit.
- **Sygnal badge counts.** Receipt badge pushes tell Apple when rooms are read, and a stored +1 badge never decrements.
- **A custom push gateway, relay or direct APNs sender.** Sygnal stays stock.
