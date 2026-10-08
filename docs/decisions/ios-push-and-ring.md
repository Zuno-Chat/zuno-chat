# iOS push and call ring

With Zuno closed, an iOS call rings from a server-sent VoIP push, while a running app still rings from sync. Messages keep `event_id_only` alert pushes, and a read-only notification service extension (NSE) fetches and decrypts their content. Android is untouched. The mechanics are in `../features/notifications.md` (push, the extension, the `zuno_push` contract) and `../features/calls.md` (the ring).

- **Ring from the server.** Apple reserves the NSE ring API, behind the filtering entitlement, for servers that cannot tell a call from a message. Zuno's server can: the `zuno_push` Synapse module watches `m.call.member`, which is clear state, and sends through stock Sygnal. A server ring needs no notification permission, room keys or entitlement.
- **Ring parity with Android.** The module decides with Synapse's own power-level and push-rule evaluation, so a closed iPhone rings exactly when a closed Android app would. A hand-written check would drift, missing room-v12 creators (every new Zuno DM) and mute settings changed in other clients.
- **Rings are sent at least once.** The module re-sends a ring that a crash interrupted, and the device drops duplicates by the call's UUID.
- **A sealed, fixed-size VoIP payload under a per-device key**, so Apple learns only that a call arrived. The key id and expiry stay in clear, so the device can drop a stale ring even before first unlock.
- **A fetching, read-only NSE.** It fetches the pushed event with a narrow module credential and decrypts it with trimmed Megolm sessions the app exports to an App Group only the two share. It never holds a Matrix token, the Olm identity or `zuno.db`.
- **Names, never silence.** A message the NSE cannot decrypt, or a reply that did not come from the module, still shows its sender and room. A call whose ring failed becomes a time-sensitive fallback notification.
- **Private by default.** One preview level drives notification text and the CallKit name, because the OS keeps what a notification showed. Thread ids and the call handle are opaque, and there are no Siri donations. Notifications are text only, since images would add a zero-click attack surface. Message pushes still show Apple the room and event ids that stock Sygnal adds.
- **Constraint.** The ring depends on `m.call.member` staying clear state. Encrypted or sticky call membership would need an explicit ring endpoint.

## Accepted costs

- Calls ring even when notifications are denied: calls are not notifications, and PushKit needs no permission.
- At preview Nothing the NSE fetches nothing, so a failed ring gets no fallback.
- A room read elsewhere while Zuno is closed keeps its badge until the next push or open, because receipt badge pushes are off.
- After a sender's key changes, their messages show names only until Zuno is opened.
- An app not opened for 30 days has an expired credential, so its notifications show names only until the next open.

## Rejected

- **Ringing from the NSE.** The entitlement is scoped to servers that cannot tell a call, the API shares PushKit's kill counter, and an NSE does not run while notifications are off.
- **The PushKit token as a Matrix pusher.** Every notifying event would become a VoIP push, and iOS requires each VoIP push to report a call.
- **`on_new_event` as the trigger.** It makes Synapse load full room state for every event on every worker.
- **`zuno.db` in the NSE.** A file lock held at suspension gets the process killed, and every key would be within the NSE's reach.
- **A Matrix token in the NSE.** A second token refresher logs the app out, and longer token lifetimes would change Android too.
- **Dart or the full SDK in the NSE.** They do not fit the extension's memory limit.
- **A plaintext VoIP payload.** It hands Apple the room, the call and the video flag.
- **A to-device key peek.** It would put the phone's Olm channels, or its device identity, in the process most exposed to hostile input.
- **The NSE as its own Matrix device.** Every sender would have to share keys with one more device per user.
- **Background refresh to fetch keys.** It runs near the user's own app opens and never after a force-quit.
- **Sygnal badge counts.** Receipt badge pushes tell Apple when rooms are read, and a stored +1 badge never decrements.
- **A custom push gateway, relay or direct APNs sender.** Sygnal stays stock.
